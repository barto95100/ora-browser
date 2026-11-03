import Foundation
@preconcurrency import WebKit

// `WKUserContentController` keeps its message handlers alive, and a page keeps
// its controller (through its web view's configuration): registering the page
// itself would make a cycle. Rule: the controller never holds anything — it
// gets one of these proxies, which hold their target weakly and relay to it.

/// Relays messages without a reply; dropped once the target is gone.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private(set) weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Relays messages that expect a reply; once the target is gone, rejects them
/// so the page's promise does not stay pending.
final class WeakScriptMessageHandlerWithReply: NSObject, WKScriptMessageHandlerWithReply {
    private(set) weak var target: WKScriptMessageHandlerWithReply?

    init(_ target: WKScriptMessageHandlerWithReply) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let target else {
            replyHandler(nil, "Handler unavailable")
            return
        }
        target.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }
}
