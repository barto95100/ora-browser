import AppKit
@preconcurrency import WebKit

/// A browser window as the extensions see it (`chrome.windows`): its tabs
/// are its loaded tabs, those of the space it shows first. Every page with
/// an extension's scripts must belong to a tab, or WebKit drops its messages.
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var window: NSWindow?
    weak var tabManager: TabManager?
    let isPrivateWindow: Bool
    private weak var manager: WebExtensionsManager?

    init(window: NSWindow, tabManager: TabManager, isPrivate: Bool, manager: WebExtensionsManager) {
        self.window = window
        self.tabManager = tabManager
        isPrivateWindow = isPrivate
        self.manager = manager
    }

    var loadedTabs: [Tab] {
        guard let manager, let tabManager else { return [] }
        return manager.loadedTabs(of: tabManager)
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let manager else { return [] }
        return loadedTabs.map { manager.adapter(for: $0) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let manager, let tab = tabManager?.activeTab, loadedTabs.contains(where: { $0.id == tab.id }) else {
            return nil
        }
        return manager.adapter(for: tab)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        if window.isZoomed { return .maximized }
        return .normal
    }

    /// WebKit shows it only to extensions allowed in private browsing.
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
        NSApp.activate()
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        window?.performClose(nil)
        completionHandler(nil)
    }
}

/// A tab as the extensions see it (`chrome.tabs`), while it has a page.
@available(macOS 15.4, *)
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var tab: Tab?
    private weak var manager: WebExtensionsManager?

    init(tab: Tab, manager: WebExtensionsManager) {
        self.tab = tab
        self.manager = manager
    }

    private var extensionWindow: ExtensionWindow? {
        guard let tabManager = tab?.tabManager else { return nil }
        return manager?.window(for: tabManager)
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        extensionWindow
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let tab, let window = extensionWindow else { return NSNotFound }
        return window.loadedTabs.firstIndex { $0.id == tab.id } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        tab?.browserPage?.extensionWebView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        tab?.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        tab?.browserPage?.extensionWebView.url ?? tab?.url
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        tab.map { $0.type != .normal } ?? false
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        guard let tab else { return false }
        return tab.tabManager?.activeTab?.id == tab.id
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !(tab?.isLoading ?? false)
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        tab?.isPlayingMedia ?? false
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let tab, let tabManager = tab.tabManager {
            tabManager.activateTab(tab)
            extensionWindow?.window?.makeKeyAndOrderFront(nil)
        }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if let tab, let tabManager = tab.tabManager {
            tabManager.closeTab(tab: tab)
        }
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        tab?.browserPage?.load(URLRequest(url: url))
        completionHandler(nil)
    }
}
