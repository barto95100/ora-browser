import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// Automatic Picture in Picture on tab switch (`togglePiPOnSwitch`).
    @MainActor
    struct AutoPiP {
        /// Replaces the page's `__triggerPiP` (app's world) with one that
        /// records its calls in the document, where the test reads them. Once
        /// the page's load is over, so its document stays.
        /// `answer`: what it says back (whether the page is to be kept for
        /// Picture in Picture).
        private func recordPiPRequests(
            of tab: Tab,
            in window: TabManagerTestWindow,
            answer: Bool = false
        ) async throws {
            await window.waitUntil("load over") { tab.browserPage?.isLoading == false }
            _ = try await evaluate(
                """
                window.__triggerPiP = (isActive = false) => {
                  document.documentElement.dataset.pip =
                    (document.documentElement.dataset.pip || '') + (isActive ? 'back;' : 'leave;');
                  return \(answer);
                };
                true
                """,
                in: tab
            )
        }

        private func isKeptForPiP(_ tab: Tab, in window: TabManagerTestWindow) -> Bool {
            window.mediaController.pictureInPictureTabs(excluding: nil).contains { $0.id == tab.id }
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

        /// A tab whose video plays keeps its page in the window from the
        /// request on, not only once in Picture in Picture: a page that left
        /// the window while entering stayed "entering" in WebKit, with no
        /// Picture in Picture window, and its tab could no longer be closed.
        @Test(arguments: [true, false])
        func aPlayingTabLeavingIsKeptWhilePiPStarts(started: Bool) async throws {
            try await withAutoPiP {
                try await TabManagerTestWindow.run { window in
                    let other = try await window.openLoaded("other")
                    let leaving = try await window.openLoaded("leaving")
                    try await recordPiPRequests(of: leaving, in: window, answer: started)
                    leaving.isPlayingMedia = true

                    window.tabManager.activateTab(other)

                    #expect(isKeptForPiP(leaving, in: window))
                    // The page's answer (handled before the next evaluation
                    // returns): kept if a change started, else let go.
                    #expect(try await pipRequests(of: leaving) == "leave;")
                    #expect(isKeptForPiP(leaving, in: window) == started)
                }
            }
        }

        /// An answer to an earlier request doesn't let go of the page kept
        /// for a later one.
        @Test func aLateAnswerKeepsTheLaterRequest() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("leaving")
                let media = window.mediaController
                let first = media.pictureInPictureWillStart(for: tab)
                let second = media.pictureInPictureWillStart(for: tab)
                media.pictureInPictureDidNotStart(for: tab, request: first)
                #expect(isKeptForPiP(tab, in: window))
                media.pictureInPictureDidNotStart(for: tab, request: second)
                #expect(!isKeptForPiP(tab, in: window))
            }
        }

        /// Picture in Picture never confirmed (macOS refused it without a
        /// word): after the deadline, the page is let go; once confirmed, it is
        /// kept.
        @Test func anEntryNeverConfirmedIsGivenUp() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("leaving")
                let media = window.mediaController
                let request = media.pictureInPictureWillStart(for: tab)
                media.pictureInPictureNotEntered(for: tab, request: request)
                #expect(!isKeptForPiP(tab, in: window))

                let confirmed = media.pictureInPictureWillStart(for: tab)
                media.receive(event: Self.event("entered"), from: tab)
                media.pictureInPictureNotEntered(for: tab, request: confirmed)
                #expect(isKeptForPiP(tab, in: window))
            }
        }

        private static func event(_ state: String) -> MediaEventPayload {
            MediaEventPayload(
                type: "pip", wasPlayed: nil, state: state, volume: nil, title: nil, hasNext: nil, hasPrevious: nil
            )
        }

        /// A tab playing nothing is not kept: no page moves on each switch.
        @Test func aSilentTabLeavingIsNotKept() async throws {
            try await withAutoPiP {
                try await TabManagerTestWindow.run { window in
                    let other = try await window.openLoaded("other")
                    let leaving = try await window.openLoaded("leaving")
                    try await recordPiPRequests(of: leaving, in: window, answer: true)

                    window.tabManager.activateTab(other)

                    #expect(!isKeptForPiP(leaving, in: window))
                    #expect(try await pipRequests(of: leaving) == "leave;")
                    #expect(!isKeptForPiP(leaving, in: window))
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
