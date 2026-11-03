import Foundation
@testable import Ombre
import SwiftData
import Testing

/// A closed window must free everything it owns: its managers, its tabs and
/// their pages (and so, for a private window, its private website data).
///
/// A "window" here is its managers, built like `OmbreRoot` builds them; closing
/// it drops the last references to them, as SwiftUI does with the window's
/// `@StateObject`s.
extension TabManagerTests {
    @MainActor
    struct WindowTeardown {
        /// Weak references to what a window owns.
        @MainActor
        private final class Survivors {
            weak var tabManager: TabManager?
            weak var mediaController: MediaController?
            weak var downloadManager: DownloadManager?
            weak var historyManager: HistoryManager?
            weak var page: BrowserPage?
            var spaceIDs: [UUID] = []

            init(_ window: TabManagerTestWindow) {
                tabManager = window.tabManager
                mediaController = window.mediaController
                downloadManager = window.downloadManager
                historyManager = window.historyManager
                spaceIDs = window.spaces().map(\.id)
            }

            /// What is still alive, by name.
            var alive: [String] {
                [
                    ("TabManager", tabManager as AnyObject?),
                    ("MediaController", mediaController),
                    ("DownloadManager", downloadManager),
                    ("HistoryManager", historyManager),
                    ("BrowserPage", page)
                ].compactMap { $0.1 == nil ? nil : $0.0 }
            }

            /// Lets pending main-queue work run, then reports what is left.
            func aliveAfterRelease(timeout: Duration = .seconds(2)) async -> [String] {
                let clock = ContinuousClock()
                let deadline = clock.now + timeout
                while !alive.isEmpty, clock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                for id in spaceIDs {
                    SettingsStore.shared.removeContainerSettings(for: id)
                }
                return alive
            }
        }

        /// Opens a window, lets `body` use it, then closes it.
        private func openAndClose(
            _ body: (TabManagerTestWindow, Survivors) async throws -> Void
        ) async throws -> Survivors {
            var window: TabManagerTestWindow? = TabManagerTestWindow()
            // swiftlint:disable:next force_unwrapping
            let survivors = Survivors(window!)
            // swiftlint:disable:next force_unwrapping
            try await body(window!, survivors)
            // swiftlint:disable:next force_unwrapping
            survivors.spaceIDs = window!.spaces().map(\.id)
            window = nil
            return survivors
        }

        /// Baseline: the test sees a window freed when nothing holds it.
        @Test func emptyWindowIsReleased() async throws {
            let survivors = try await openAndClose { _, _ in }
            let alive = await survivors.aliveAfterRelease()
            #expect(alive.isEmpty, "Still alive: \(alive)")
        }

        /// A tab restored from the database, never loaded.
        @Test func windowWithUnloadedTabIsReleased() async throws {
            let survivors = try await openAndClose { window, _ in
                try window.addUnloadedTab("restored", order: 1, in: window.activeSpace)
            }
            let alive = await survivors.aliveAfterRelease()
            #expect(alive.isEmpty, "Still alive: \(alive)")
        }

        /// A tab with its page loaded (a private window's page).
        @Test func windowWithLoadedPageIsReleased() async throws {
            let survivors = try await openAndClose { window, survivors in
                let tab = try await window.openLoaded("loaded")
                survivors.page = tab.browserPage
                #expect(survivors.page != nil)
            }
            let alive = await survivors.aliveAfterRelease()
            #expect(alive.isEmpty, "Still alive: \(alive)")
        }
    }

    /// A page is loaded 10 ms after it is created: by then it may have been
    /// destroyed (tab closed or unloaded) or replaced.
    @MainActor
    struct DeferredLoad {
        /// Lets the deferred load (10 ms) run.
        private func letDeferredLoadRun() async {
            try? await Task.sleep(for: .milliseconds(100))
        }

        @Test func pageDestroyedBeforeItsLoadIsNotLoaded() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try window.open("destroyed")
                weak var weakPage = tab.browserPage
                #expect(weakPage != nil)
                #expect(!tab.isWebViewReady)

                tab.destroyWebView()
                await letDeferredLoadRun()

                #expect(tab.browserPage == nil)
                #expect(!tab.isWebViewReady)
                // Not even kept alive by the pending load.
                #expect(weakPage == nil)
            }
        }

        @Test func replacedPageIsNotLoadedButItsReplacementIs() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try window.open("replaced")
                weak var weakOldPage = tab.browserPage

                // As a reload for new privacy settings does.
                tab.destroyWebView()
                tab.restoreTransientState(
                    historyManager: window.historyManager,
                    downloadManager: window.downloadManager,
                    tabManager: window.tabManager,
                    isPrivate: true
                )
                let newPage = try #require(tab.browserPage)
                await window.waitUntil("new page ready") { tab.isWebViewReady }

                #expect(tab.browserPage === newPage)
                #expect(weakOldPage == nil)
            }
        }
    }
}
