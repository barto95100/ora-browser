import Foundation
@testable import Ora
import SwiftData
import Testing

extension TabManagerTests {
    /// Spaces: creating, switching, activating a tab of another space, deleting.
    @MainActor
    struct Spaces {
        @Test func createContainerActivatesNewSpaceWithoutActiveTab() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                try window.open("tab")

                let work = window.createSpace("Work")

                #expect(window.spaces().count == 2)
                #expect(work.id != defaultSpace.id)
                #expect(work.name == "Work")
                #expect(work.emoji == "•")
                #expect(work.tabs.isEmpty)
                #expect(window.tabManager.activeContainer?.id == work.id)
                #expect(window.tabManager.activeTab == nil)
            }
        }

        @Test func activateContainerActivatesItsLastTabOnlyIfLoaded() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                let older = try await window.openLoaded("older")
                let newer = try await window.openLoaded("newer")
                older.lastAccessedAt = Date(timeIntervalSinceNow: -100)
                newer.lastAccessedAt = Date(timeIntervalSinceNow: -50)
                let work = window.createSpace("Work")

                window.tabManager.activateContainer(defaultSpace)
                #expect(window.tabManager.activeContainer?.id == defaultSpace.id)
                #expect(window.tabManager.activeTab?.id == newer.id)
                #expect(try #require(newer.lastAccessedAt) > Date(timeIntervalSinceNow: -5))

                // The most recent tab is not loaded: no active tab, even though
                // a loaded one exists.
                window.tabManager.activateContainer(work)
                window.addUnloadedTab(
                    "unloaded",
                    order: 3,
                    in: defaultSpace,
                    lastAccessedAt: Date(timeIntervalSinceNow: 10)
                )
                window.tabManager.activateContainer(defaultSpace)
                #expect(window.tabManager.activeContainer?.id == defaultSpace.id)
                #expect(window.tabManager.activeTab == nil)
            }
        }

        @Test func activateContainerTreatsTabsNeverAccessedAsMostRecent() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                try await window.openLoaded("loaded")
                window.addUnloadedTab("never", order: 2, in: defaultSpace, lastAccessedAt: nil)
                let work = window.createSpace("Work")
                window.tabManager.activateContainer(work)

                window.tabManager.activateContainer(defaultSpace)

                // BUG: (ONG-16) a tab never accessed counts as accessed "now" here
                // (`?? Date()`, elsewhere `?? .distantPast`): it wins, and since
                // it is not loaded, no tab is activated.
                #expect(window.tabManager.activeTab == nil)
            }
        }

        @Test func activateTabByIDSwitchesToItsSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                let work = window.createSpace("Work")
                let target = window.addUnloadedTab("target", order: 1, in: work)
                window.tabManager.activateContainer(defaultSpace)
                let active = try await window.openLoaded("active")

                window.tabManager.activateTab(id: target.id)

                #expect(window.tabManager.activeContainer?.id == work.id)
                #expect(window.tabManager.activeTab?.id == target.id)
                #expect(target.maybeIsActive)
                // BUG: the previous tab still believes it is active: when the
                // space's last tab is not loaded, `activateContainer` sets
                // `activeTab = nil` without clearing its `maybeIsActive`, so
                // `activateTab` no longer sees it. Its header-color snapshots
                // (`maintainSnapShots`) keep running in the background.
                #expect(active.maybeIsActive)
                // Activating loads the page.
                #expect(target.browserPage != nil)
            }
        }

        @Test func activateTabOfAnotherSpaceMakesItsSpaceActive() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                let work = window.createSpace("Work")
                let target = window.addUnloadedTab("target", order: 1, in: work)
                window.tabManager.activateContainer(defaultSpace)
                let workAccess = work.lastAccessedAt

                window.tabManager.activateTab(target)

                #expect(window.tabManager.activeContainer?.id == work.id)
                #expect(window.tabManager.activeTab?.id == target.id)
                #expect(work.lastAccessedAt > workAccess)
            }
        }

        @Test func deletingActiveSpaceDeletesItsContentAndActivatesAnother() async throws {
            try await TabManagerTestWindow.run { window in
                let work = window.createSpace("Work")
                window.addUnloadedTab("work", order: 1, in: work)
                let deleted = window.createSpace("Deleted")
                let deletedID = deleted.id
                window.remember(deleted)
                let loaded = try await window.openLoaded("loaded")
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: deleted)
                window.tabManager.createFolder(in: deleted, with: pinned)
                let history = History(
                    url: TabManagerTestWindow.url("visited"),
                    title: "Visited",
                    faviconURL: TabManagerTestWindow.url("favicon.ico"),
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    visitCount: 1,
                    container: deleted
                )
                window.modelContext.insert(history)
                try window.modelContext.save()
                #expect(window.tabManager.activeTab?.id == loaded.id)

                window.tabManager.deleteContainer(deleted)

                await window.waitUntil("space deleted") {
                    !window.spaces().contains { $0.id == deletedID }
                        && window.tabManager.activeContainer != nil
                }
                let tabs = try window.modelContext.fetch(FetchDescriptor<Tab>())
                let folders = try window.modelContext.fetch(FetchDescriptor<Folder>())
                let histories = try window.modelContext.fetch(FetchDescriptor<History>())
                #expect(tabs.count == 1)
                #expect(tabs.first?.container.id == work.id)
                #expect(folders.isEmpty)
                #expect(histories.isEmpty)
                // The page of the deleted tab is torn down.
                #expect(loaded.browserPage == nil)
                // The most recently accessed space takes over; its last tab is
                // not loaded, so none is active.
                #expect(window.tabManager.activeContainer?.id == work.id)
                #expect(window.tabManager.activeTab == nil)
            }
        }
    }
}
