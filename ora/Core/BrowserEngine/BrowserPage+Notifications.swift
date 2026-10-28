import Foundation
@preconcurrency import WebKit

/// Web notifications (`new Notification(...)`), which WebKit does not offer to
/// apps. `WebNotificationScript` gives pages the standard API; this bridge
/// answers it: the permission comes from the site's saved choice (asked with
/// the usual permission prompt), and notifications of allowed sites go to the
/// page delegate, which shows them with macOS notifications.
final class WebNotificationBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let messageName = "oraNotifications"

    /// Weak: the content controller keeps its handlers alive.
    weak var page: BrowserPage?

    init(page: BrowserPage) {
        self.page = page
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        // Popups share the page's configuration; frames get no notifications.
        guard let page, message.webView === page.webView, message.frameInfo.isMainFrame,
              let delegate = page.delegate,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String
        else {
            replyHandler(nil, "Notifications are not available")
            return
        }
        let origin = Self.url(of: message.frameInfo.securityOrigin)

        switch action {
        case "permission":
            let decision = delegate.browserPage(page, queryPermission: .notifications, origin: origin)
            replyHandler(Self.permissionName(for: decision), nil)
        case "request":
            delegate.browserPage(page, requestPermission: .notifications, origin: origin) { decision in
                replyHandler(Self.permissionName(for: decision), nil)
            }
        case "show":
            guard delegate.browserPage(page, queryPermission: .notifications, origin: origin) == .grant,
                  let notification = BrowserWebNotification(message: body, origin: origin)
            else {
                replyHandler(false, nil)
                return
            }
            delegate.browserPage(page, showNotification: notification)
            replyHandler(true, nil)
        case "close":
            if let id = body["id"] as? String {
                delegate.browserPage(page, closeNotification: id)
            }
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "Unknown action")
        }
    }

    /// `Notification.permission` for a saved decision.
    static func permissionName(for decision: BrowserPermissionDecision) -> String {
        switch decision {
        case .grant: "granted"
        case .deny: "denied"
        case .prompt: "default"
        }
    }

    private static func url(of origin: WKSecurityOrigin) -> URL? {
        URL(string: "\(origin.protocol)://\(origin.host):\(origin.port)")
    }
}

extension BrowserWebNotification {
    /// Reads a "show" message of `WebNotificationScript`.
    init?(message: [String: Any], origin: URL?) {
        guard let id = message["id"] as? String, let title = message["title"] as? String else { return nil }
        let tag = (message["tag"] as? String) ?? ""
        self.init(
            id: id,
            title: title,
            body: (message["body"] as? String) ?? "",
            tag: tag.isEmpty ? nil : tag,
            isSilent: (message["silent"] as? Bool) ?? false,
            origin: origin
        )
    }
}

extension BrowserPage {
    func installWebNotifications(in contentController: WKUserContentController) {
        contentController.addScriptMessageHandler(
            WebNotificationBridge(page: self),
            contentWorld: .page,
            name: WebNotificationBridge.messageName
        )
        contentController.addUserScript(WKUserScript(
            source: WebNotificationScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
    }

    /// Tells the page one of its notifications was clicked in Notification
    /// Center ("click"), so it can show what the notification was about.
    func dispatchNotificationEvent(_ type: String, notificationID: String) {
        guard let arguments = try? JSONSerialization.data(withJSONObject: [notificationID, type]),
              let list = String(data: arguments, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript(
            "window.__oraNotificationEvent && window.__oraNotificationEvent(...\(list))",
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }
}
