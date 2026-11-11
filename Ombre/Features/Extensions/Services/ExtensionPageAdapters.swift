import AppKit
@preconcurrency import WebKit

/// A page outside the sidebar's tabs, as the extensions see it: Peek (a tab
/// of its browser window) or a popup (the only tab of its popup window).
/// Without it, WebKit drops the messages of the extensions' scripts in that
/// page ("Tab not found"): Bitwarden's menu under a login field stays empty.
@available(macOS 15.4, *)
@MainActor
final class ExtensionPageTab: NSObject, WKWebExtensionTab {
    weak var page: BrowserPage?
    /// Its browser window (Peek) or its popup window.
    weak var extensionWindow: (any WKWebExtensionWindow)?
    /// Closes Peek or the popup (`tabs.remove`).
    var closeAction: (() -> Void)?
    /// In a private window: what extensions decide there stays in memory.
    let isPrivatePage: Bool

    init(page: BrowserPage, window: (any WKWebExtensionWindow)?, isPrivate: Bool, close: (() -> Void)?) {
        self.page = page
        extensionWindow = window
        isPrivatePage = isPrivate
        closeAction = close
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        extensionWindow
    }

    /// The popup's only tab; Peek comes after its window's tabs.
    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        if extensionWindow is ExtensionPopupWindow { return 0 }
        return (extensionWindow as? ExtensionWindow)?.loadedTabs.count ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        page?.extensionWebView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        page?.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        page?.extensionWebView.url
    }

    /// Shown in front of its window while open.
    func isSelected(for context: WKWebExtensionContext) -> Bool {
        true
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !(page?.extensionWebView.isLoading ?? false)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        page?.load(URLRequest(url: url))
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        closeAction?()
        completionHandler(nil)
    }
}

/// A popup window (`window.open` with a size) as the extensions see it.
@available(macOS 15.4, *)
@MainActor
final class ExtensionPopupWindow: NSObject, WKWebExtensionWindow {
    weak var window: NSWindow?
    var tab: ExtensionPageTab?
    let isPrivateWindow: Bool

    init(window: NSWindow, isPrivate: Bool) {
        self.window = window
        isPrivateWindow = isPrivate
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        tab.map { [$0] } ?? []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .popup
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        window?.isMiniaturized == true ? .minimized : .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        isPrivateWindow
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        window?.screen?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        window?.performClose(nil)
        completionHandler(nil)
    }
}

@available(macOS 15.4, *)
extension WebExtensionsManager {
    /// Peek's page: a tab of its browser window for the extensions.
    func peekOpened(_ page: BrowserPage, in tabManager: TabManager, isPrivate: Bool, close: @escaping () -> Void) {
        let key = ObjectIdentifier(page)
        guard pageTabs[key]?.page == nil else { return }
        let tab = ExtensionPageTab(page: page, window: window(for: tabManager), isPrivate: isPrivate, close: close)
        pageTabs[key] = tab
        controller.didOpenTab(tab)
    }

    /// A popup's page: the only tab of its popup window.
    func popupOpened(_ page: BrowserPage, window: NSWindow, isPrivate: Bool, close: @escaping () -> Void) {
        let key = ObjectIdentifier(page)
        guard pageTabs[key]?.page == nil else { return }
        let popupWindow = ExtensionPopupWindow(window: window, isPrivate: isPrivate)
        let tab = ExtensionPageTab(page: page, window: popupWindow, isPrivate: isPrivate, close: close)
        popupWindow.tab = tab
        pageTabs[key] = tab
        popupWindows[ObjectIdentifier(window)] = popupWindow
        controller.didOpenWindow(popupWindow)
        controller.didOpenTab(tab)
    }

    /// Peek or the popup closed, or Peek became a tab (it is then told as one).
    func pageClosed(_ page: BrowserPage) {
        guard let tab = pageTabs.removeValue(forKey: ObjectIdentifier(page)) else { return }
        let popupWindow = tab.extensionWindow as? ExtensionPopupWindow
        controller.didCloseTab(tab, windowIsClosing: popupWindow != nil)
        if let popupWindow, let window = popupWindow.window {
            popupWindows[ObjectIdentifier(window)] = nil
            controller.didCloseWindow(popupWindow)
        }
    }

    func pageChanged(_ page: BrowserPage, url: Bool, title: Bool, loading: Bool) {
        guard let tab = pageTabs[ObjectIdentifier(page)] else { return }
        var properties: WKWebExtension.TabChangedProperties = []
        if url { properties.insert(.URL) }
        if title { properties.insert(.title) }
        if loading { properties.insert(.loading) }
        guard !properties.isEmpty else { return }
        controller.didChangeTabProperties(properties, for: tab)
    }

    /// Peek open in `window`: the tab in front there, for the extensions.
    func peekTab(in window: ExtensionWindow) -> ExtensionPageTab? {
        pageTabs.values.first { $0.page != nil && $0.extensionWindow === window }
    }
}
