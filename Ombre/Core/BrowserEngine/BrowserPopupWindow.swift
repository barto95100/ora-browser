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
    /// The window of the page that opened it: the popup closes with it.
    private weak var openerWindow: NSWindow?
    /// The page that opened it (or opened the popup that opened it): its
    /// downloads go to that page's tab.
    private weak var opener: BrowserPage?
    /// The origin of the frame that opened it (perhaps a third-party frame):
    /// the site a page it wrote into a blank popup comes from.
    private var openerOrigin: URL?
    private var observations: [NSKeyValueObservation] = []

    /// Whether the window is an open popup (⌘W then closes it, see `OmbreCommands`).
    static func isPopupWindow(_ window: NSWindow) -> Bool {
        openPopups.contains { $0.window === window }
    }

    /// Closes the popups opened from `window`, and theirs: they share their
    /// opener's process and website data (private ones too), which must not
    /// outlive its window.
    static func closePopups(openedFrom window: NSWindow) {
        for popup in openPopups where popup.openerWindow === window {
            popup.window.close()
        }
    }

    /// The open popups opened from `window` (not counting theirs).
    static func popupCount(openedFrom window: NSWindow) -> Int {
        openPopups.filter { $0.openerWindow === window }.count
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
        openerWindow: NSWindow?,
        opener: BrowserPage?,
        openerOrigin: URL? = nil
    ) -> WKWebView {
        let popup = BrowserPopupWindow(
            configuration: configuration,
            frame: frame(for: windowFeatures, openerWindow: openerWindow)
        )
        popup.openerWindow = openerWindow
        popup.opener = opener
        popup.openerOrigin = openerOrigin
        popup.updateTitle()
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
        // The site actually loaded is the window's title, never the page's
        // own title, which could pretend to be another site (MOT-09); the
        // page's title is the subtitle.
        observations = [
            webView.observe(\.url) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateTitle() }
            },
            webView.observe(\.title) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateTitle() }
            }
        ]
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

    /// The site the page comes from as the title; the page's own title only
    /// under it, never alone.
    private func updateTitle() {
        let site = PopupTitle.title(for: webView.url, openerURL: openerOrigin)
        window.title = site
        window.subtitle = site.isEmpty ? "" : (webView.title ?? "")
    }

    func windowWillClose(_ notification: Notification) {
        observations = []
        webView.stopLoading()
        Self.openPopups.remove(self)
        Self.closePopups(openedFrom: window)
    }
}

/// The popup's title: the site the page comes from, said not private over
/// HTTP. A page without a host of its own (`about:blank` written by its
/// opener, `blob:`) shows the site it really comes from, never nothing (its
/// own title would then be all that shows).
enum PopupTitle {
    /// The origin of a frame, as an address (`https://host[:port]`).
    @MainActor static func origin(of frame: WKFrameInfo) -> URL? {
        let origin = frame.securityOrigin
        guard !origin.host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 { components.port = origin.port }
        return components.url
    }

    static func title(for url: URL?, openerURL: URL? = nil) -> String {
        guard let url else { return "" }
        let scheme = url.scheme?.lowercased() ?? ""
        if let host = url.host(), !host.isEmpty {
            return scheme == "https" ? host : "Not Secure — \(host)"
        }
        if scheme == "blob", let inner = URL(string: String(url.absoluteString.dropFirst("blob:".count))),
           inner.host() != nil
        {
            return title(for: inner)
        }
        if scheme == "about", let openerURL, openerURL.host() != nil {
            return title(for: openerURL)
        }
        return url.absoluteString.isEmpty ? "" : (scheme.isEmpty ? url.absoluteString : "\(scheme):")
    }
}

extension BrowserPopupWindow: WKNavigationDelegate {
    /// Files are downloaded, not shown, like in a tab, to its opener's tab.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(BrowserDownloadPolicy.isDownload(navigationResponse) ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard let url = navigationResponse.response.url else { return }
        hand(download, url: url)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard let url = navigationAction.request.url else { return }
        hand(download, url: url)
    }

    private func hand(_ download: WKDownload, url: URL) {
        guard let opener else {
            download.cancel { _ in }
            return
        }
        opener.delegate?.browserPage(
            opener,
            didStartDownload: BrowserDownloadTask(download: download, originalURL: url)
        )
    }
}

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
        Self.open(
            configuration: configuration,
            windowFeatures: windowFeatures,
            openerWindow: window,
            opener: opener,
            openerOrigin: PopupTitle.origin(of: navigationAction.sourceFrame)
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}
