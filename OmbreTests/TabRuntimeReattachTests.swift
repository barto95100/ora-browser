import Foundation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    /// A pinned tab left alone for a while came back as an endless spinner:
    /// nothing kept its object, the database handed out a new one with no
    /// page, and showing it made pages it never loaded.
    @MainActor
    struct RuntimeReattach {
        /// Opens a pinned tab with its page, then another tab, and keeps only
        /// the pinned tab's id: nothing of the test holds its object.
        private func pinnedTabLeftAlone(in window: TabManagerTestWindow) async throws -> UUID {
            let pinned = try await window.openLoaded("pinned")
            window.tabManager.togglePinTab(pinned)
            _ = try await window.openLoaded("other")
            return pinned.id
        }

        @Test func aTabWithAPageStaysTheSameObject() async throws {
            try await TabManagerTestWindow.run { window in
                let id = try await pinnedTabLeftAlone(in: window)
                for _ in 0 ..< 3 {
                    try? window.modelContext.save()
                    _ = window.tabs(withID: id)
                    try? await Task.sleep(for: .milliseconds(20))
                }

                let pinned = try #require(window.tabs(withID: id).first)
                #expect(pinned.browserPage != nil)
                #expect(pinned.isWebViewReady)
                #expect(pinned.browserPage === window.tabManager.existingRuntime(for: id)?.page)
            }
        }

        /// The tab lost its runtime (a new object for it): shown again, it
        /// gets the window's page back instead of making pages it never loads.
        @Test func aTabThatLostItsRuntimeGetsItsPageBack() async throws {
            try await TabManagerTestWindow.run { window in
                let id = try await pinnedTabLeftAlone(in: window)
                let pinned = try #require(window.tabs(withID: id).first)
                let page = try #require(pinned.browserPage)

                // What a new object for the same tab looks like.
                pinned.pageRuntime = nil
                pinned.tabManager = nil

                window.tabManager.activateTab(pinned)
                // The views ask again a moment later (sidebar tap, BrowserView).
                for _ in 0 ..< 2 {
                    try? await Task.sleep(for: .milliseconds(20))
                    if !pinned.isWebViewReady {
                        pinned.restoreTransientState(
                            historyManager: window.historyManager,
                            downloadManager: window.downloadManager,
                            tabManager: window.tabManager,
                            isPrivate: true
                        )
                    }
                }
                #expect(pinned.isWebViewReady)
                #expect(pinned.browserPage === page)
                #expect(window.tabManager.existingRuntime(for: id)?.page === page)
            }
        }
    }
}
