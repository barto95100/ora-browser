import Foundation
import Observation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    /// Two windows on the same database: what one saves shows in the other
    /// at once, like Arc (ONG-02).
    @MainActor
    struct WindowSync {
        private func tab(_ id: UUID, in window: TabManagerTestWindow) -> Tab? {
            window.tabs(withID: id).first
        }

        /// A window catches up on the main queue's next turn.
        private func caughtUp() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { DispatchQueue.main.async { continuation.resume() } }
            }
        }

        @Test func tabOpenedInOneWindowShowsInTheOther() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let space = try second.activeSpace
                #expect(try space.id == (first.activeSpace).id)
                nonisolated(unsafe) var redrawn = false
                withObservationTracking { _ = space.tabs } onChange: { redrawn = true }

                let opened = try first.open("opened")
                await caughtUp()

                #expect(space.tabs.contains { $0.id == opened.id })
                #expect(redrawn)
            }
        }

        @Test func renamedSpaceAndTitleShowInTheOtherWindow() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let opened = try first.open("page")
                await caughtUp()
                let shown = try #require(tab(opened.id, in: second))
                nonisolated(unsafe) var redrawn = false
                withObservationTracking { _ = shown.title } onChange: { redrawn = true }

                opened.title = "New title"
                try first.activeSpace.name = "Work"
                first.modelContext.saveOrLog("test")
                await caughtUp()

                #expect(shown.title == "New title")
                #expect(redrawn)
                #expect(try second.activeSpace.name == "Work")
            }
        }

        /// The other window showed the tab: it shows another one and lets go
        /// of the page.
        @Test func tabClosedInOneWindowLeavesTheOther() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let kept = try first.open("kept")
                let closing = try first.open("closing")
                await caughtUp()
                let keptThere = try #require(tab(kept.id, in: second))
                let shownThere = try #require(tab(closing.id, in: second))
                second.tabManager.activateTab(keptThere)
                second.tabManager.activateTab(shownThere)
                #expect(shownThere.runtime != nil)

                await first.close(closing)
                await second.waitUntil("other window caught up") { second.tabManager.activeTab?.id != closing.id }

                #expect(second.tabManager.activeTab?.id == kept.id)
                #expect(shownThere.browserPage == nil)
                #expect(second.tabManager.existingRuntime(for: closing.id) == nil)
                #expect(try !(second.activeSpace).tabs.contains { $0.id == closing.id })
            }
        }

        /// Its split partner deleted elsewhere, a tab is shown alone, as when
        /// the window closes the partner itself.
        @Test func splitPartnerClosedElsewhereLeavesTheTabAlone() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let other = try first.open("other")
                let left = try first.open("left")
                let right = try first.open("right")
                await caughtUp()
                let leftThere = try #require(tab(left.id, in: second))
                let rightThere = try #require(tab(right.id, in: second))
                let otherThere = try #require(tab(other.id, in: second))
                second.tabManager.activateTab(otherThere)
                second.tabManager.activateTab(leftThere)
                second.tabManager.openInSplitView(rightThere)
                second.tabManager.activateTab(rightThere)
                await caughtUp()

                await first.close(right)
                await second.waitUntil("other window caught up") { second.tabManager.activeTab?.id != right.id }

                #expect(second.tabManager.activeTab?.id == left.id)
            }
        }

        @Test func spaceDeletedInOneWindowLeavesTheOther() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let home = try first.activeSpace
                let work = first.createSpace("Work")
                first.tabManager.activateContainer(work)
                let page = try first.open("work page")
                await caughtUp()
                let workThere = try #require(second.spaces().first { $0.id == work.id })
                second.tabManager.activateContainer(workThere)
                #expect(second.tabManager.activeTab?.id == page.id)

                first.tabManager.activateContainer(home)
                await first.tabManager.deleteContainer(work).value
                await caughtUp()

                #expect(second.tabManager.activeContainer?.id == home.id)
                #expect(second.tabManager.existingRuntime(for: page.id) == nil)
            }
        }

        /// The last space deleted: the window that deleted it makes a new one,
        /// which the other window then shows.
        @Test func lastSpaceDeletedLeavesTheOtherOnTheNewOne() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let only = try first.activeSpace
                await first.tabManager.deleteContainer(only).value
                await caughtUp()

                let replacement = try first.activeSpace
                first.remember(replacement)
                #expect(replacement.id != only.id)
                #expect(second.tabManager.activeContainer?.id == replacement.id)
            }
        }

        /// A tab made in one window and shown in the other keeps its space
        /// in both (two contexts used to lose it, then crash on reading it).
        @Test func tabShownInTheOtherWindowKeepsItsSpace() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let opened = try first.open("page")
                await caughtUp()
                let there = try #require(tab(opened.id, in: second))

                // The case seen on 05/11: activated and saved in the other
                // window, then read again in both and in the database.
                second.tabManager.activateTab(there)
                second.modelContext.saveOrLog("test")
                await caughtUp()
                first.tabManager.activateTab(opened)
                first.modelContext.saveOrLog("test")
                await caughtUp()

                #expect(opened.parentContainer != nil)
                #expect(there.parentContainer != nil)
                #expect(second.tabManager.activeTab?.parentContainer != nil)
                let openedID = opened.id
                let stored = try ModelContext(first.modelContainer)
                    .fetch(FetchDescriptor<Tab>(predicate: #Predicate { $0.id == openedID }))
                #expect(stored.count == 1)
                #expect(try stored.first?.parentContainer?.id == (first.activeSpace).id)
            }
        }

        /// A save of nothing a window shows from its spaces (history…) costs
        /// the other windows nothing.
        @Test func unrelatedSaveIsIgnored() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let space = try second.activeSpace
                nonisolated(unsafe) var redrawn = false
                withObservationTracking { _ = space.tabs } onChange: { redrawn = true }

                first.modelContext.insert(Download(originalURL: TabManagerTestWindow.url("a.zip"), fileName: "a.zip"))
                first.modelContext.saveOrLog("test")
                await caughtUp()

                #expect(!redrawn)
                #expect(second.tabManager.pendingSync == nil)
            }
        }

        /// Both windows change the same tab: neither stops saving.
        @Test func sameTabChangedInBothWindowsStillSaves() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                let opened = try first.open("page")
                await caughtUp()
                let there = try #require(tab(opened.id, in: second))

                there.title = "From the second window"
                opened.title = "From the first window"
                first.modelContext.saveOrLog("first")
                await caughtUp()

                #expect(second.modelContext.saveOrLog("second"))
                there.title = "Again"
                #expect(second.modelContext.saveOrLog("second again"))
                let stored = try ModelContext(first.modelContainer).fetch(FetchDescriptor<Tab>())
                #expect(stored.first { $0.id == opened.id }?.title == "Again")
            }
        }

        /// A tab changed here and deleted in the other window: this window
        /// still saves.
        @Test func tabChangedHereDeletedThereStillSaves() async throws {
            try await TabManagerTestWindow.runTwo { first, second in
                _ = try first.open("kept")
                let closing = try first.open("closing")
                await caughtUp()
                let there = try #require(tab(closing.id, in: second))

                there.title = "Changed here"
                await first.close(closing)
                await caughtUp()

                #expect(second.modelContext.saveOrLog("second"))
                try second.activeSpace.name = "Renamed"
                #expect(second.modelContext.saveOrLog("second again"))
                // Not brought back by this window's save.
                let stored = try ModelContext(first.modelContainer).fetch(FetchDescriptor<Tab>())
                #expect(!stored.contains { $0.id == closing.id })
            }
        }
    }
}
