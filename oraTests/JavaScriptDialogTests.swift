import Foundation
@testable import Ora
import Testing

/// `alert`, `confirm` and `prompt` (MOT-03): never from a page that isn't
/// shown, and the user can stop a page that keeps asking.
struct JavaScriptDialogPolicyTests {
    @Test func pageNotShownIsAnsweredWithoutADialog() {
        var policy = JavaScriptDialogPolicy()
        #expect(policy.decide(isPageShown: false) == .refuse)
        // Not counted: its first shown dialog offers nothing yet.
        #expect(policy.decide(isPageShown: true) == .show(offersToStopDialogs: false))
    }

    @Test func secondDialogOffersToStopThePage() {
        var policy = JavaScriptDialogPolicy()
        #expect(policy.decide(isPageShown: true) == .show(offersToStopDialogs: false))
        #expect(policy.decide(isPageShown: true) == .show(offersToStopDialogs: true))
        #expect(policy.decide(isPageShown: true) == .show(offersToStopDialogs: true))
    }

    /// `while (true) alert(1)`: once stopped, the page gets its answers
    /// right away and the window stays usable.
    @Test func stoppedPageIsAnsweredWithoutADialog() {
        var policy = JavaScriptDialogPolicy()
        _ = policy.decide(isPageShown: true)
        _ = policy.decide(isPageShown: true)
        policy.stopDialogs()
        for _ in 0 ..< 100 {
            #expect(policy.decide(isPageShown: true) == .refuse)
        }
    }

    @Test func dialogSaysWhichSiteAsks() {
        let dialog = BrowserJavaScriptDialog(kind: .alert, message: "Hi", host: "example.com")
        #expect(dialog.title == "The page at example.com says:")
        // A `data:` page or a sandboxed frame has no site.
        let anonymous = BrowserJavaScriptDialog(kind: .alert, message: "Hi", host: "")
        #expect(anonymous.title == "This page says:")
    }

    @Test func newDocumentStartsAfresh() {
        var policy = JavaScriptDialogPolicy()
        _ = policy.decide(isPageShown: true)
        _ = policy.decide(isPageShown: true)
        policy.stopDialogs()

        policy.pageDidCommitNewDocument()

        #expect(policy.decide(isPageShown: true) == .show(offersToStopDialogs: false))
    }
}

extension TabManagerTests {
    /// A tab's page asks for a dialog.
    @MainActor
    struct TabJavaScriptDialogs {
        private let dialog = BrowserJavaScriptDialog(kind: .confirm, message: "Leave?", host: "example.com")

        /// A page in no window (a background tab) can't show a dialog over
        /// the tab in front: it is answered at once.
        @Test func pageInNoWindowIsRefusedAtOnce() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("background")
                let page = try #require(tab.browserPage)
                let delegate = try #require(tab.pageDelegate)
                #expect(page.window == nil)

                var reply: BrowserJavaScriptDialogReply?
                delegate.browserPage(page, runJavaScriptDialog: dialog) { reply = $0 }

                #expect(reply == .refused)
            }
        }

        /// Closing the page with no dialog open does nothing.
        @Test func dismissingWithoutADialogDoesNothing() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("quiet")
                let delegate = try #require(tab.pageDelegate)
                delegate.dismissDialog()
                tab.destroyWebView()
                #expect(tab.browserPage == nil)
            }
        }

        /// A page that loads a new document may show dialogs again.
        @Test func committedNavigationResetsThePolicy() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("navigating")
                let page = try #require(tab.browserPage)
                let delegate = try #require(tab.pageDelegate)
                delegate.dialogPolicy.stopDialogs()

                delegate.browserPage(page, didUpdateNavigation: BrowserNavigationEvent(
                    phase: .committed, url: tab.url, title: nil, progress: 0.5, isLoading: true
                ))

                #expect(!delegate.dialogPolicy.isStopped)
            }
        }
    }
}
