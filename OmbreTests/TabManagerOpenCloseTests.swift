import Foundation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    @MainActor
    struct Launch {
        @Test func emptyDatabaseCreatesDefaultSpaceWithoutActiveTab() async throws {
            try await TabManagerTestWindow.run { window in
                let spaces = window.spaces()
                #expect(spaces.count == 1)
                #expect(spaces.first?.name == "Default")
                #expect(window.tabManager.activeContainer?.id == spaces.first?.id)
                #expect(window.tabManager.activeTab == nil)
            }
        }

        @Test func relaunchResumesLastSpaceAndItsLastTabWithoutLoadingIt() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                window.addUnloadedTab("default", order: 1, in: defaultSpace)
                let work = window.createSpace("Work")
                window.addUnloadedTab("old", order: 1, in: work, lastAccessedAt: Date(timeIntervalSinceNow: -100))
                let recent = window.addUnloadedTab("recent", order: 2, in: work, lastAccessedAt: Date())
                defaultSpace.lastAccessedAt = Date(timeIntervalSinceNow: -1000)
                work.lastAccessedAt = Date()
                try window.modelContext.save()

                // A new window on the same database, as after a relaunch.
                let context = ModelContext(window.modelContainer)
                let relaunched = TabManager(
                    modelContainer: window.modelContainer,
                    modelContext: context,
                    mediaController: MediaController(),
                    downloadManager: DownloadManager(modelContainer: window.modelContainer, modelContext: context),
                    historyManager: HistoryManager(modelContainer: window.modelContainer, modelContext: context)
                )

                #expect(relaunched.activeContainer?.id == work.id)
                #expect(relaunched.activeTab?.id == recent.id)
                #expect(relaunched.activeTab?.maybeIsActive == true)
                #expect(relaunched.activeTab?.browserPage == nil)
                #expect(relaunched.activeTab?.isWebViewReady == false)
            }
        }
    }

    @MainActor
    struct Open {
        @Test func openTabAddsItToActiveSpaceAndActivatesIt() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let first = try window.open("first")
                let second = try window.open("second")

                #expect(space.tabs.count == 2)
                #expect(second.container.id == space.id)
                #expect(window.tabManager.activeTab?.id == second.id)
                #expect(second.maybeIsActive)
                #expect(!first.maybeIsActive)
                #expect(second.type == .normal)
                // The host stands for the title until the page reports its own.
                #expect(second.title == "127.0.0.1")
                // Order: number of tabs in the space + 1, so the newest is on top.
                #expect(first.order == 1)
                #expect(second.order == 2)
                // The page is created right away and loaded 10 ms later.
                #expect(second.browserPage != nil)
                await window.waitUntil("page ready") { second.isWebViewReady }
            }
        }

        @Test func openTabWithoutFocusLeavesActiveTabAndCreatesNoPage() async throws {
            try await TabManagerTestWindow.run { window in
                let active = try window.open("active")
                let background = try window.open("background", focus: false)

                #expect(window.tabManager.activeTab?.id == active.id)
                #expect(try window.activeSpace.tabs.contains { $0.id == background.id })
                #expect(background.browserPage == nil)
                #expect(!background.isWebViewReady)
            }
        }

        @Test func openTabWithURLWithoutHostReturnsNil() async throws {
            try await TabManagerTestWindow.run { window in
                let blank = try #require(URL(string: "about:blank"))
                let tab = window.tabManager.openTab(url: blank, historyManager: window.historyManager, isPrivate: true)

                #expect(tab == nil)
                #expect(try window.activeSpace.tabs.isEmpty)
            }
        }

        @Test func aNewTabGoesOnTopAfterAClose() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try window.open("first", focus: false)
                try window.open("second", focus: false)
                let third = try window.open("third", focus: false)
                await window.close(first)

                let fourth = try window.open("fourth", focus: false)

                // Above every tab of its section (before: `tabs.count + 1`, 3,
                // the same order as "third").
                #expect(third.order == 3)
                #expect(fourth.order == 4)
            }
        }
    }

    @MainActor
    struct Close {
        @Test func closingActiveTabActivatesMostRecentLoadedTab() async throws {
            try await TabManagerTestWindow.run { window in
                let older = try await window.openLoaded("older")
                let newer = try await window.openLoaded("newer")
                let active = try await window.openLoaded("active")
                older.lastAccessedAt = Date(timeIntervalSinceNow: -100)
                newer.lastAccessedAt = Date(timeIntervalSinceNow: -50)

                await window.close(active)

                #expect(window.tabManager.activeTab?.id == newer.id)
                #expect(newer.maybeIsActive)
                #expect(window.tabs(withID: active.id).isEmpty)
                #expect(try window.activeSpace.tabs.count == 2)
            }
        }

        @Test func closingActiveTabNeverPicksAnUnloadedTab() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                window.addUnloadedTab("unloaded", order: 1, in: space, lastAccessedAt: Date())
                let active = try await window.openLoaded("active")

                await window.close(active)

                #expect(window.tabManager.activeTab == nil)
                #expect(space.tabs.count == 1)
            }
        }

        @Test func closingLastTabLeavesNoActiveTab() async throws {
            try await TabManagerTestWindow.run { window in
                let only = try await window.openLoaded("only")

                await window.close(only)

                #expect(window.tabManager.activeTab == nil)
                #expect(try window.activeSpace.tabs.isEmpty)
                #expect(try window.activeSpace.id == window.tabManager.activeContainer?.id)
            }
        }

        @Test func closingInactiveTabKeepsActiveTab() async throws {
            try await TabManagerTestWindow.run { window in
                let inactive = try await window.openLoaded("inactive")
                let active = try await window.openLoaded("active")

                await window.close(inactive)

                #expect(window.tabManager.activeTab?.id == active.id)
                #expect(window.tabs(withID: inactive.id).isEmpty)
            }
        }

        @Test func closingPinnedTabOnlyUnloadsItAndCannotBeReopened() async throws {
            try await TabManagerTestWindow.run { window in
                let pinned = try await window.openLoaded("pinned")
                window.tabManager.togglePinTab(pinned)
                let active = try await window.openLoaded("active")

                await window.close(pinned)

                #expect(window.tabs(withID: pinned.id).count == 1)
                #expect(pinned.type == .pinned)
                #expect(pinned.browserPage == nil)
                #expect(!pinned.isWebViewReady)
                // Not remembered for ⌘Z.
                window.tabManager.restoreLastTab()
                #expect(window.tabManager.activeTab?.id == active.id)
                #expect(try window.activeSpace.tabs.count == 2)
            }
        }

        @Test func closingOneSideOfSplitActivatesTheOtherSide() async throws {
            try await TabManagerTestWindow.run { window in
                let left = try await window.openLoaded("left")
                let right = try await window.openLoaded("right")
                let other = try await window.openLoaded("other")
                window.tabManager.activateTab(left)
                window.tabManager.openInSplitView(right)
                #expect(window.tabManager.activeTab?.id == right.id)
                #expect(left.splitRightTabID == right.id)
                other.lastAccessedAt = Date(timeIntervalSinceNow: 100)

                await window.close(right)

                // The partner wins over the most recently accessed tab.
                #expect(window.tabManager.activeTab?.id == left.id)
                #expect(left.splitRightTabID == nil)
            }
        }

        @Test func closingSameTabTwiceRemembersItOnce() async throws {
            try await TabManagerTestWindow.run { window in
                let earlier = try window.open("earlier", focus: false)
                let earlierID = earlier.id
                let closed = try window.open("closed", focus: false)
                let closedID = closed.id
                try window.open("active")
                await window.close(earlier)

                // A double click on the close button (ONG-12).
                window.tabManager.closeTab(tab: closed)
                window.tabManager.closeTab(tab: closed)
                await window.waitUntilClosed(closed)
                window.tabManager.restoreLastTab()
                window.tabManager.restoreLastTab()
                try window.modelContext.save()

                // The second ⌘Z brings back the tab closed before.
                #expect(window.tabs(withID: closedID).count == 1)
                #expect(window.tabs(withID: earlierID).count == 1)
            }
        }
    }
}
