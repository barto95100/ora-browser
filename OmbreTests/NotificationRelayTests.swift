import Foundation
@testable import Ombre
import Testing
import WebKit

/// The notifications API reaches the app through the app's world: the page
/// has no `window.webkit` of Ombre's to see or post to (it set Ombre apart
/// from Safari, whose pages have none).
@MainActor
struct NotificationRelayTests {
    /// Grants notifications to every site (or the decision set), for the
    /// API to have an answer.
    private final class GrantingDelegate: BrowserPageDelegate {
        var decision = BrowserPermissionDecision.grant

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
            decision
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

    private func makePage(_ delegate: GrantingDelegate) -> BrowserPage {
        BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: true
            ),
            delegate: delegate
        )
    }

    private func waitFor(_ page: BrowserPage, _ condition: String) async throws {
        for _ in 0 ..< 100 where await evaluateInPage(page, condition) as? Bool != true {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The site's saved choice is there when the page's first script runs,
    /// not "default" until the app answers (MOT-18).
    @Test(arguments: [
        (BrowserPermissionDecision.grant, "granted"),
        (.deny, "denied"),
        (.prompt, "default")
    ])
    func permissionIsKnownFromTheStart(decision: BrowserPermissionDecision, expected: String) async throws {
        let delegate = GrantingDelegate()
        delegate.decision = decision
        let page = makePage(delegate)
        defer { page.teardown() }
        let html = "<script>window.initial = Notification.permission</script><p>page</p>"
        page.extensionWebView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        try await waitFor(page, "typeof window.initial === 'string'")

        #expect(await evaluateInPage(page, "window.initial") as? String == expected)
    }

    /// `navigator.permissions.query` gives WebKit's own `PermissionStatus`
    /// (not a stand-in object), with the site's choice: WebKit alone says
    /// "prompt" for notifications whatever the choice (MOT-18).
    @Test func permissionsQueryIsWebKits() async throws {
        let delegate = GrantingDelegate()
        let page = makePage(delegate)
        defer { page.teardown() }
        let html = """
        <script>
        navigator.permissions.query({ name: 'notifications' }).then((status) => {
          window.result = [
            status instanceof PermissionStatus, status.state, status.name,
            Object.getOwnPropertyNames(status).length, Object.keys(navigator.permissions).length
          ].join(' ');
        });
        </script>
        """
        page.extensionWebView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        try await waitFor(page, "typeof window.result === 'string'")

        let result = await evaluateInPage(page, "window.result") as? String
        #expect(result == "true granted notifications 0 0", "\(String(describing: result))")
    }

    /// A new choice replaces the API's script only: the others (the app's,
    /// an extension's) stay, the same objects.
    @Test func otherScriptsStayWhenTheChoiceChanges() {
        let delegate = GrantingDelegate()
        let page = makePage(delegate)
        defer { page.teardown() }
        let controller = page.extensionWebView.configuration.userContentController
        let extensionScript = WKUserScript(source: "1", injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        controller.addUserScript(extensionScript)
        let before = controller.userScripts.count

        page.prepareNotifications(for: URL(string: "https://granted.example/"))
        delegate.decision = .deny
        page.prepareNotifications(for: URL(string: "https://denied.example/"))

        #expect(controller.userScripts.count == before)
        #expect(controller.userScripts.contains { $0 === extensionScript })
        #expect(controller.userScripts.contains { $0.source.contains("denied.example") })
        #expect(!controller.userScripts.contains { $0.source.contains("granted.example") })
    }

    /// The choice given to the script is the site's only.
    @Test func initialStateIsForItsSiteOnly() throws {
        let url = try #require(URL(string: "https://Example.com:8443/path"))
        #expect(WebNotificationScript.InitialState(url: url, permission: "granted")?.origin
            == "https://example.com:8443")
        let standard = try #require(URL(string: "https://example.com:443/"))
        #expect(WebNotificationScript.InitialState(url: standard, permission: "denied")?.origin
            == "https://example.com")
        #expect(WebNotificationScript.InitialState(url: url, permission: "default") == nil)
        let http = try #require(URL(string: "http://example.com/"))
        #expect(WebNotificationScript.InitialState(url: http, permission: "granted") == nil)
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
