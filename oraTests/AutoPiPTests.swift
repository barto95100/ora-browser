import Foundation
@testable import Ora
import Testing

extension TabManagerTests {
    /// Automatic Picture in Picture on tab switch (`togglePiPOnSwitch`).
    @MainActor
    struct AutoPiP {
        /// Replaces the page's `__triggerPiP` (app's world) with one that
        /// records its calls in the document, where the test reads them. Once
        /// the page's load is over, so its document stays.
        private func recordPiPRequests(of tab: Tab, in window: TabManagerTestWindow) async throws {
            await window.waitUntil("load over") { tab.browserPage?.isLoading == false }
            _ = try await evaluate(
                """
                window.__triggerPiP = (isActive = false) => {
                  document.documentElement.dataset.pip =
                    (document.documentElement.dataset.pip || '') + (isActive ? 'back;' : 'leave;');
                };
                true
                """,
                in: tab
            )
        }

        private func pipRequests(of tab: Tab) async throws -> String {
            try await evaluate("document.documentElement.dataset.pip || ''", in: tab) as? String ?? ""
        }

        private func evaluate(_ script: String, in tab: Tab) async throws -> Any? {
            let page = try #require(tab.browserPage)
            return try await withCheckedThrowingContinuation { continuation in
                page.evaluateJavaScript(script) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: value)
                    }
                }
            }
        }

        /// Runs `body` with automatic Picture in Picture on, then restores the setting.
        private func withAutoPiP(_ body: () async throws -> Void) async throws {
            let settings = SettingsStore.shared
            let saved = settings.autoPiPEnabled
            settings.autoPiPEnabled = true
            defer { settings.autoPiPEnabled = saved }
            try await body()
        }

        @Test func leavingTabIsAskedToGoToPiP() async throws {
            try await withAutoPiP {
                try await TabManagerTestWindow.run { window in
                    let other = try await window.openLoaded("other")
                    let leaving = try await window.openLoaded("leaving")
                    try await recordPiPRequests(of: leaving, in: window)

                    window.tabManager.activateTab(other)

                    #expect(try await pipRequests(of: leaving) == "leave;")
                }
            }
        }

        /// Closing a tab whose video plays stops it; asking it to go to
        /// Picture in Picture first left a black Picture in Picture window.
        @Test func closingTabIsNotAskedToGoToPiP() async throws {
            try await withAutoPiP {
                try await TabManagerTestWindow.run { window in
                    let other = try await window.openLoaded("other")
                    let closing = try await window.openLoaded("closing")
                    try await recordPiPRequests(of: closing, in: window)

                    window.tabManager.closeTab(tab: closing)

                    // Read before the closing tab's page is torn down
                    // (evaluations run in order).
                    #expect(try await pipRequests(of: closing) == "")
                    #expect(window.tabManager.activeTab?.id == other.id)
                    await window.waitUntilClosed(closing)
                }
            }
        }

        /// A pinned tab is only unloaded when closed: shown again, it goes to
        /// Picture in Picture again when left.
        @Test func reopenedPinnedTabGoesToPiPAgain() async throws {
            try await withAutoPiP {
                try await TabManagerTestWindow.run { window in
                    let space = try window.activeSpace
                    let other = try await window.openLoaded("other")
                    let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: space)
                    window.tabManager.activateTab(pinned)
                    await window.waitUntil("pinned page ready") { pinned.isWebViewReady }
                    await window.close(pinned)

                    window.tabManager.activateTab(pinned)
                    await window.waitUntil("pinned page ready again") { pinned.isWebViewReady }
                    try await recordPiPRequests(of: pinned, in: window)
                    window.tabManager.activateTab(other)

                    #expect(try await pipRequests(of: pinned) == "leave;")
                }
            }
        }
    }
}
