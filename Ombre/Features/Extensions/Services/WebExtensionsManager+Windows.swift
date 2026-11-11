import AppKit
@preconcurrency import WebKit

/// The extensions' own pages outside their popup (a window or a tab they
/// open, their options page), and their popup when they ask for it.
@available(macOS 15.4, *)
extension WebExtensionsManager {
    /// Key of the extensions menu (🧩) among the popup anchors.
    static let menuAnchorKey = ""

    /// A page for one of the extensions' own URLs: made with that extension's
    /// configuration (WebKit cancels the navigation otherwise), nil for any
    /// other URL.
    func pageConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard url.scheme == ExtensionBaseURL.scheme else { return nil }
        return controller.extensionContext(for: url)?.webViewConfiguration
    }

    /// `windows.create`. The extension's own page (Bitwarden's unlock window):
    /// a small window of its own. Anything else: tabs in the front window
    /// (an extension opens no browser window).
    func openWindow(
        _ configuration: WKWebExtension.WindowConfiguration,
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        let urls = configuration.tabURLs
        if urls.count == 1, configuration.tabs.isEmpty, let url = urls.first,
           controller.extensionContext(for: url) === context
        {
            return openExtensionWindow(url, frame: configuration.frame, for: context)
        }
        // A private window only when asked, and allowed.
        let window = if configuration.shouldBePrivate {
            context.hasAccessToPrivateData ? orderedWindows.first(where: \.isPrivateWindow) : nil
        } else {
            focusedNormalWindow
        }
        // Tabs to move: not done.
        guard configuration.tabs.isEmpty, let window, let tabManager = window.tabManager, !urls.isEmpty
        else { return nil }
        for (index, url) in urls.enumerated() {
            let tab = tabManager.openTab(
                url: url,
                historyManager: tabManager.historyManager,
                downloadManager: tabManager.downloadManager,
                focusAfterOpening: index == 0,
                isPrivate: window.isPrivateWindow
            )
            if let tab { tabOpened(tab) }
        }
        if configuration.shouldBeFocused { window.window?.makeKeyAndOrderFront(nil) }
        return window
    }

    /// The page in a small window, beside the front normal window's tab
    /// (where the links it opens go).
    private func openExtensionWindow(
        _ url: URL,
        frame: CGRect,
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        // Beside a private window only for an extension allowed there.
        let browserWindow = focusedNormalWindow ?? (context.hasAccessToPrivateData ? focusedWindow : nil)
        guard let configuration = context.webViewConfiguration,
              let browserWindow,
              let tabManager = browserWindow.tabManager,
              let spaceID = tabManager.activeTab?.container.id ?? tabManager.activeContainer?.id
        else { return nil }
        let popupContext = if let tab = tabManager.activeTab {
            PopupContext(tab: tab)
        } else {
            PopupContext(
                spaceID: spaceID,
                isPrivate: false,
                privateSession: nil,
                downloadManager: tabManager.downloadManager
            )
        }
        let page = Self.makeExtensionPage(configuration: configuration, spaceID: spaceID)
        let screen = browserWindow.window?.screen ?? NSScreen.main
        let windowFrame = Self.extensionWindowFrame(
            requested: frame,
            around: browserWindow.window?.frame,
            visible: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let window = BrowserPopupWindow.openExtensionPage(
            url,
            page: page,
            title: context.webExtension.displayName ?? "",
            frame: NSWindow.contentRect(
                forFrameRect: windowFrame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable]
            ),
            context: popupContext
        )
        return popupWindows[ObjectIdentifier(window)]
    }

    /// A page with an extension's configuration, without Ombre's scripts:
    /// the page is the extension's, not a website.
    static func makeExtensionPage(configuration: WKWebViewConfiguration, spaceID: UUID) -> BrowserPage {
        let page = BrowserPage(
            profile: BrowserEngine.shared.makeProfile(identifier: spaceID, isPrivate: false),
            configuration: BrowserPageConfiguration.ombreDefault(
                userScripts: [],
                privacySettings: SettingsStore.shared.privacySettings(for: spaceID),
                enablesWebNotifications: false
            ),
            delegate: nil,
            webKitConfiguration: configuration
        )
        page.isExtensionPage = true
        return page
    }

    /// The window's frame (screen coordinates): what the extension asked
    /// for (each value may be missing: NaN), else 400 × 600 centered on
    /// `around`; always on the visible screen.
    static func extensionWindowFrame(requested: CGRect, around: NSRect?, visible: NSRect) -> NSRect {
        func value(_ number: CGFloat) -> CGFloat? {
            number.isFinite ? number : nil
        }
        let width = min(max(value(requested.size.width) ?? 400, 200), visible.width)
        let height = min(max(value(requested.size.height) ?? 600, 150), visible.height)
        let reference = around ?? visible
        var origin = NSPoint(
            x: value(requested.origin.x) ?? (reference.midX - width / 2),
            y: value(requested.origin.y) ?? (reference.midY - height / 2)
        )
        origin.x = min(max(origin.x, visible.minX), visible.maxX - width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - height)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    // MARK: - Popup

    /// Its popup, asked by the extension (Bitwarden asks its app for it on
    /// Safari: `showPopover`), for the front window's tab.
    func showPopup(of context: WKWebExtensionContext) {
        guard let window = Self.window(
            for: nil,
            focused: focusedWindow,
            focusedNormal: focusedNormalWindow,
            allowsPrivate: context.hasAccessToPrivateData
        ) else { return }
        performAction(context, for: window.tabManager?.activeTab, anchor: nil, window: window.window)
    }

    /// An extension's button (`id`), or the extensions menu (`menuAnchorKey`).
    func registerPopupAnchor(_ view: NSView, extensionID: String) {
        popupAnchors.setObject(extensionID as NSString, forKey: view)
    }

    /// Where its popup shows in `window`: its button, else the extensions
    /// menu, if shown there; nil: centered on the window.
    func popupAnchor(for extensionID: String, in window: NSWindow?) -> NSView? {
        var anchors: [(view: NSView, id: String)] = []
        for case let view as NSView in popupAnchors.keyEnumerator() {
            if let id = popupAnchors.object(forKey: view) { anchors.append((view, id as String)) }
        }
        return Self.popupAnchor(for: extensionID, in: window, among: anchors)
    }

    static func popupAnchor(
        for extensionID: String,
        in window: NSWindow?,
        among anchors: [(view: NSView, id: String)]
    ) -> NSView? {
        guard let window else { return nil }
        let shown = anchors.filter { anchor in
            anchor.view.window === window && !anchor.view.isHiddenOrHasHiddenAncestor
                && !anchor.view.visibleRect.isEmpty
        }
        return shown.first { $0.id == extensionID }?.view ?? shown.first { $0.id == menuAnchorKey }?.view
    }

    /// Shows the popup under its anchor, or centered on the front window.
    func present(_ popover: NSPopover, for context: WKWebExtensionContext) -> Bool {
        let window = popupWindow ?? focusedWindow?.window
        let clicked = popupAnchor.flatMap { $0.window == nil ? nil : $0 }
        popupAnchor = nil
        popupWindow = nil
        if let anchor = clicked ?? popupAnchor(for: context.uniqueIdentifier, in: window) {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            return true
        }
        guard let content = window?.contentView else { return false }
        // Its top edge at the point, so that it hangs centered.
        let height = popover.contentSize.height
        let point = NSRect(
            x: content.bounds.midX,
            y: min(content.bounds.midY + height / 2, content.bounds.maxY),
            width: 1,
            height: 1
        )
        popover.show(relativeTo: point, of: content, preferredEdge: .minY)
        return true
    }
}
