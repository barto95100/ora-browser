import Foundation
@testable import Ombre
import Testing
import WebKit

/// The notifications API reaches the app through the app's world: the page
/// has no `window.webkit` of Ombre's to see or post to (it set Ombre apart
/// from Safari, whose pages have none).
@MainActor
struct NotificationRelayTests {
    /// Grants notifications to every site, for the API to have an answer.
    private final class GrantingDelegate: BrowserPageDelegate {
        func browserPage(_ page: BrowserPage, decidePolicyFor action: BrowserNavigationAction)
            -> BrowserNavigationActionDisposition
        {
            .allow
        }
        func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition) {}
        func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {}
        func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {}
        func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {}
        func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?) {}
        func browserPage(_ page: BrowserPage, didReceiveScriptMessage message: BrowserScriptMessage) {}
        func browserPage(
            _ page: BrowserPage, requestPermission permission: BrowserPermissionKind, origin: URL?,
            decisionHandler: @escaping (BrowserPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
        func browserPage(_ page: BrowserPage, queryPermission permission: BrowserPermissionKind, origin: URL?)
            -> BrowserPermissionDecision
        {
            .grant
        }
        func browserPage(
            _ page: BrowserPage, runOpenPanelWith options: BrowserOpenPanelOptions,
            completion: @escaping ([URL]?) -> Void
        ) {
            completion(nil)
        }
        func browserPage(
            _ page: BrowserPage, runJavaScriptDialog dialog: BrowserJavaScriptDialog,
            completion: @escaping (BrowserJavaScriptDialogReply) -> Void
        ) {}
        func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {}
        func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool {
            true
        }
        func browserPage(_ page: BrowserPage, didBlockContentFrom url: URL) {}
        func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool {
            false
        }
        func browserPage(_ page: BrowserPage, showNotification notification: BrowserWebNotification) {}
        func browserPage(_ page: BrowserPage, closeNotification id: String) {}
        func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState) {}
        func browserPageWebContentProcessDidTerminate(_ page: BrowserPage) {}
    }

    private func evaluateInPage(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.extensionWebView.evaluateJavaScript(script, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    @Test func pageGetsTheAPIButNoBridge() async throws {
        let delegate = GrantingDelegate()
        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: true
            ),
            delegate: delegate
        )
        defer { page.teardown() }
        page.extensionWebView.loadHTMLString("<p>page</p>", baseURL: URL(string: "https://example.com/"))
        for _ in 0 ..< 100 where await evaluateInPage(page, "Notification.permission") as? String != "granted" {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await evaluateInPage(page, "Notification.permission") as? String == "granted")
        #expect(await evaluateInPage(page, "typeof window.webkit") as? String == "undefined")

        // A page watching every event's detail never sees the channel.
        _ = await evaluateInPage(page, """
        window.seen = [];
        const original = Object.getOwnPropertyDescriptor(CustomEvent.prototype, 'detail');
        Object.defineProperty(CustomEvent.prototype, 'detail', {
          get() { window.seen.push(this.type); return original.get.call(this); }
        });
        Notification.requestPermission().then(() => { window.answered = true; });
        true
        """)
        for _ in 0 ..< 50 where await evaluateInPage(page, "window.answered === true") as? Bool != true {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await evaluateInPage(page, "window.answered === true") as? Bool == true)
        #expect(await evaluateInPage(page, "window.seen.length") as? Int == 0)
    }
}
