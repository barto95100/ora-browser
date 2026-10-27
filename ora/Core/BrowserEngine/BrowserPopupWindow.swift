import AppKit
@preconcurrency import WebKit

/// A popup opened by a page with `window.open(url, name, "width=…,height=…")`,
/// typically a "Sign in with…" window. Like Safari, it gets its own small
/// window and stays linked to the page that opened it (`window.opener`,
/// `postMessage`, `window.close()`), which a new tab could not do.
@MainActor
final class BrowserPopupWindow: NSObject, NSWindowDelegate {
    /// Open popups, kept alive until their window closes.
    private static var openPopups: Set<BrowserPopupWindow> = []

    private let window: NSWindow
    private let webView: WKWebView
    private var titleObservation: NSKeyValueObservation?

    /// Whether the window is an open popup (⌘W then closes it, see `OraCommands`).
    static func isPopupWindow(_ window: NSWindow) -> Bool {
        openPopups.contains { $0.window === window }
    }

    /// Whether WebKit's window features ask for a popup window rather than a tab.
    static func isPopup(_ features: WKWindowFeatures) -> Bool {
        features.width != nil || features.height != nil
    }

    /// Creates the popup's web view with WebKit's configuration (required: it
    /// shares the opener's process and data) and shows it; WebKit then loads it.
    static func open(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerWindow: NSWindow?
    ) -> WKWebView {
        let popup = BrowserPopupWindow(
            configuration: configuration,
            frame: frame(for: windowFeatures, openerWindow: openerWindow)
        )
        openPopups.insert(popup)
        popup.window.makeKeyAndOrderFront(nil)
        popup.window.makeFirstResponder(popup.webView)
        return popup.webView
    }

    private init(configuration: WKWebViewConfiguration, frame: NSRect) {
        webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: configuration)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        // Typing goes to the page right away (fields the page focuses itself).
        window.initialFirstResponder = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        titleObservation = webView.observe(\.title) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.window.title = webView.title ?? ""
            }
        }
    }

    /// The size the page asked for, placed where it asked (screen coordinates
    /// from the top-left, like the web) or centered over the opener's window.
    private static func frame(for features: WKWindowFeatures, openerWindow: NSWindow?) -> NSRect {
        let screen = openerWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(CGFloat(features.width?.doubleValue ?? 500), visible.width)
        let height = min(CGFloat(features.height?.doubleValue ?? 600), visible.height)

        var origin: NSPoint
        if let left = features.x?.doubleValue, let top = features.y?.doubleValue, let screenFrame = screen?.frame {
            origin = NSPoint(x: screenFrame.minX + left, y: screenFrame.maxY - top - height)
        } else {
            let reference = openerWindow?.frame ?? visible
            origin = NSPoint(x: reference.midX - width / 2, y: reference.midY - height / 2)
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - height)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation = nil
        webView.stopLoading()
        Self.openPopups.remove(self)
    }
}

extension BrowserPopupWindow: WKNavigationDelegate {}

extension BrowserPopupWindow: WKUIDelegate {
    /// `window.close()` from the popup.
    func webViewDidClose(_ webView: WKWebView) {
        window.close()
    }

    /// A popup opening a popup.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        Self.open(configuration: configuration, windowFeatures: windowFeatures, openerWindow: window)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
}
