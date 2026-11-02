import Foundation
@testable import Ora
import Testing
import WebKit

/// A page must be freed once nothing holds it, even without `teardown()`:
/// its `WKUserContentController` must not keep it (or its web view) alive.
@MainActor
struct BrowserPageReleaseTests {
    private func makePage() -> BrowserPage {
        BrowserPage(
            // Private: nothing written on disk by the test.
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .oraDefault(
                userScripts: [],
                privacySettings: SpacePrivacySettings(),
                // Also install the notification bridge (off in private).
                enablesWebNotifications: true
            ),
            delegate: nil
        )
    }

    @Test func pageIsReleasedWithoutTeardown() {
        weak var weakPage: BrowserPage?
        autoreleasepool {
            let page = makePage()
            weakPage = page
        }
        #expect(weakPage == nil)
    }

    @Test func pageIsReleasedAfterTeardown() {
        weak var weakPage: BrowserPage?
        autoreleasepool {
            let page = makePage()
            weakPage = page
            page.teardown()
        }
        #expect(weakPage == nil)
    }

    @Test func pageOwnsItsNotificationBridge() {
        let page = makePage()
        #expect(page.notificationBridge?.page === page)
        page.teardown()
    }

    @Test func proxyDoesNotRetainItsTarget() {
        var proxy: WeakScriptMessageHandler?
        autoreleasepool {
            let target = RecordingHandler()
            proxy = WeakScriptMessageHandler(target)
            #expect(proxy?.target === target)
        }
        #expect(proxy?.target == nil)
    }

    @Test func replyProxyDoesNotRetainItsTarget() {
        var proxy: WeakScriptMessageHandlerWithReply?
        autoreleasepool {
            let target = RecordingReplyHandler()
            proxy = WeakScriptMessageHandlerWithReply(target)
            #expect(proxy?.target === target)
        }
        #expect(proxy?.target == nil)
    }
}

private final class RecordingHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive _: WKScriptMessage) {}
}

private final class RecordingReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(
        _: WKUserContentController,
        didReceive _: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        replyHandler(nil, nil)
    }
}
