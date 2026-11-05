import Foundation
@testable import Ombre
import SwiftData
import Testing

/// One cleaner for the app: each window unloads its pages and closes its
/// own copies of old tabs, never one a window of its database uses, and
/// never offered back by ⌘Z. The tests pass their own windows to `clean`: never the open ones.
@MainActor
@Suite(.serialized)
struct TabCleanerTests {
    /// Past any removal delay ("Never" is 365 days).
    private let muchLater = Date().addingTimeInterval(400 * 24 * 60 * 60)

    private func makeSecondWindow(of window: TabManagerTestWindow) -> TabManager {
        TabManager(
            modelContainer: window.modelContainer,
            modelContext: ModelContext(window.modelContainer),
            mediaController: MediaController(),
            downloadManager: window.downloadManager,
            historyManager: window.historyManager
        )
    }

    private func tab(_ id: UUID, in manager: TabManager) -> Tab? {
        (try? manager.modelContext.fetch(FetchDescriptor<Tab>()))?.first { $0.id == id }
    }

    @Test func windowsSignInAndOutWithOneTimer() async throws {
        try await TabManagerTestWindow.run { window in
            #expect(TabCleaner.shared.isCleaning(window.tabManager))
            // With leeway, so the system can group it with other work.
            #expect(TabCleaner.shared.timerTolerance == 10)

            window.tabManager.tearDown()

            #expect(!TabCleaner.shared.isCleaning(window.tabManager))
        }
    }

    @Test func aSpaceAutoClearIsNotOfferedBackByUndo() async throws {
        try await TabManagerTestWindow.run { window in
            let space = try window.activeSpace
            window.remember(space)
            SettingsStore.shared.setAutoClearTabsAfter(.oneHour, for: space.id)
            let old = window.addUnloadedTab("old", order: 1, in: space)

            // Two hours later: the space's auto-clear, not the general removal.
            window.tabManager.closeOldTabs(sparing: [], now: Date().addingTimeInterval(2 * 60 * 60))
            await window.waitUntil("old tab closed") { !space.tabs.contains { $0.id == old.id } }

            // Before, the space's auto-clear fed ⌘Z.
            #expect(window.tabManager.recentlyClosedTabs.isEmpty)
        }
    }

    @Test func eachWindowClosesItsOwnCopy() async throws {
        try await TabManagerTestWindow.run { window in
            let second = makeSecondWindow(of: window)
            defer { second.tearDown() }
            let space = try window.activeSpace
            let old = window.addUnloadedTab("old", order: 1, in: space)
            try window.modelContext.save()
            let mine = try #require(tab(old.id, in: window.tabManager))
            let theirs = try #require(tab(old.id, in: second))

            TabCleaner.shared.clean([window.tabManager, second], now: muchLater)

            // No copy left pointing to a deleted row.
            #expect(mine.isClosing)
            #expect(theirs.isClosing)
        }
    }

    @Test func aTabInUseInAnyWindowIsSpared() async throws {
        try await TabManagerTestWindow.run { window in
            let space = try window.activeSpace
            let inUse = window.addUnloadedTab("in use", order: 1, in: space)
            let old = window.addUnloadedTab("old", order: 2, in: space)

            // `inUse`: shown, playing or recording in another window.
            window.tabManager.closeOldTabs(sparing: [inUse.id], now: muchLater)

            #expect(!inUse.isClosing)
            #expect(old.isClosing)
        }
    }

    @Test func theShownTabIsInUse() async throws {
        try await TabManagerTestWindow.run { window in
            let shown = try await window.openLoaded("shown")

            #expect(window.tabManager.tabsInUse().contains(shown.id))
        }
    }
}
