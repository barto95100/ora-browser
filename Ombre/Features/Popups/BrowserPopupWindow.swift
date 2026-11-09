import AppKit
import Combine
import SwiftUI
@preconcurrency import WebKit

/// A popup opened by a page with `window.open(url, name, "width=…,height=…")`,
/// typically a "Sign in with…" window. Like Safari, it gets its own small
/// window and stays linked to the page that opened it (`window.opener`,
/// `postMessage`, `window.close()`), which a new tab could not do. Its page
/// behaves like a tab of its space (see `PopupPage`).
@MainActor
final class BrowserPopupWindow: NSObject, NSWindowDelegate {
    /// Open popups, kept alive until their window closes.
    private static var openPopups: Set<BrowserPopupWindow> = []

    private let window: NSWindow
    let popupPage: PopupPage
    /// The window of the page that opened it: the popup closes with it.
    private weak var openerWindow: NSWindow?
    /// The origin of the frame that opened it (perhaps a third-party frame):
    /// the site a page it wrote into a blank popup comes from.
    private var openerOrigin: URL?
    /// The permission prompt over the page, while one waits.
    private var promptView: NSView?
    private var promptObservation: AnyCancellable?

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

    /// Closes the popups of a space being deleted.
    static func closePopups(inSpace spaceID: UUID) {
        for popup in openPopups where popup.popupPage.context.spaceID == spaceID {
            popup.window.close()
        }
    }

    /// The open popups opened from `window` (not counting theirs).
    static func popupCount(openedFrom window: NSWindow) -> Int {
        openPopups.filter { $0.openerWindow === window }.count
    }

    /// The open popup showing `webView`, if any.
    static func popup(showing webView: WKWebView) -> BrowserPopupWindow? {
        openPopups.first { $0.popupPage.page.webView === webView }
    }

    /// Whether WebKit's window features ask for a popup window rather than a tab.
    static func isPopup(_ features: WKWindowFeatures) -> Bool {
        features.width != nil || features.height != nil
    }

    /// Creates the popup's page with WebKit's configuration (required: it
    /// shares the opener's process and data), in `context`'s space, and shows
    /// it; WebKit then loads it.
    @discardableResult
    static func open(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerWindow: NSWindow?,
        opener: BrowserPage?,
        openerOrigin: URL? = nil,
        context: PopupContext
    ) -> WKWebView {
        let page = PopupPage(configuration: configuration, opener: opener, context: context)
        let popup = BrowserPopupWindow(
            popup: page,
            frame: frame(for: windowFeatures, openerWindow: openerWindow)
        )
        popup.openerWindow = openerWindow
        popup.openerOrigin = openerOrigin
        popup.updateTitle()
        openPopups.insert(popup)
        popup.window.makeKeyAndOrderFront(nil)
        popup.window.makeFirstResponder(page.page.webView)
        return page.page.webView
    }

    private init(popup: PopupPage, frame: NSRect) {
        popupPage = popup
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let pageView = popup.page.contentView
        pageView.frame = content.bounds
        pageView.autoresizingMask = [.width, .height]
        content.addSubview(pageView)
        window.contentView = content
        // Typing goes to the page right away (fields the page focuses itself).
        window.initialFirstResponder = popup.page.webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        // The site actually loaded is the window's title, never the page's
        // own title, which could pretend to be another site (MOT-09); the
        // page's title is the subtitle.
        popup.pageDidChange = { [weak self] in self?.updateTitle() }
        popup.closeWindow = { [weak self] in self?.window.close() }
        promptObservation = popup.$permissionRequest.sink { [weak self] request in
            self?.showPrompt(request)
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

    /// The site the page comes from as the title; the page's own title only
    /// under it, never alone.
    private func updateTitle() {
        let page = popupPage.page
        let site = PopupTitle.title(for: page.currentURL, openerURL: openerOrigin)
        window.title = site
        window.subtitle = site.isEmpty ? "" : (page.title ?? "")
    }

    /// The tab's permission prompt, at the top of the page.
    private func showPrompt(_ request: SitePermissionRequest?) {
        promptView?.removeFromSuperview()
        promptView = nil
        guard let request, let content = window.contentView else { return }
        let prompt = NSHostingView(rootView: SitePermissionPromptView(
            request: request,
            isPrivate: popupPage.context.isPrivate
        ) { [weak popupPage] granted, remember in
            popupPage?.answerPermissionRequest(granted: granted, remember: remember)
        })
        prompt.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            prompt.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        ])
        promptView = prompt
    }

    func windowWillClose(_ notification: Notification) {
        promptObservation = nil
        popupPage.pageDidChange = nil
        popupPage.closeWindow = nil
        popupPage.close()
        Self.openPopups.remove(self)
        Self.closePopups(openedFrom: window)
    }
}
