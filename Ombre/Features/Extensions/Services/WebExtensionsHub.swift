import AppKit
import Foundation

/// What the rest of Ombre tells the extensions, on any macOS: the calls do
/// nothing before macOS 15.4, where WebKit has no extensions. Called on the
/// main thread only (tabs, windows and pages live there).
@MainActor
enum WebExtensionsHub {
    static var isSupported: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    /// At launch, before the first page: pages get the extension controller.
    static func start() {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.start()
        }
    }

    /// A browser window; a private one shows only to the extensions allowed
    /// in private browsing.
    static func registerWindow(_ window: NSWindow, tabManager: TabManager, isPrivate: Bool) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.registerWindow(window, tabManager: tabManager, isPrivate: isPrivate)
        }
    }

    static func activeTabChanged(in tabManager: TabManager) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.activeTabChanged(in: tabManager)
        }
    }

    /// A tab got its page.
    static func tabOpened(_ tab: Tab) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.tabOpened(tab)
        }
    }

    /// A tab's page went away (closed, or unloaded).
    static func tabClosed(_ tab: Tab) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.tabClosed(tab)
        }
    }

    /// Peek's page shows (a tab of its window for the extensions).
    static func peekOpened(
        _ page: BrowserPage,
        in tabManager: TabManager,
        isPrivate: Bool,
        close: @escaping () -> Void
    ) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.peekOpened(page, in: tabManager, isPrivate: isPrivate, close: close)
        }
    }

    /// A popup window's page shows (its only tab).
    static func popupOpened(_ page: BrowserPage, window: NSWindow, isPrivate: Bool, close: @escaping () -> Void) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.popupOpened(page, window: window, isPrivate: isPrivate, close: close)
        }
    }

    /// Peek or a popup went (or Peek became a tab).
    static func pageClosed(_ page: BrowserPage) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.pageClosed(page)
        }
    }

    static func pageChanged(_ page: BrowserPage, url: Bool = false, title: Bool = false, loading: Bool = false) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.pageChanged(page, url: url, title: title, loading: loading)
        }
    }

    /// The extensions' items for the page's context menu.
    static func contextMenuItems(for page: BrowserPage) -> [NSMenuItem] {
        if #available(macOS 15.4, *) {
            return WebExtensionsManager.shared.contextMenuItems(for: page)
        }
        return []
    }

    static func tabChanged(_ tab: Tab, url: Bool = false, title: Bool = false, loading: Bool = false) {
        if #available(macOS 15.4, *) {
            WebExtensionsManager.shared.tabChanged(tab, url: url, title: title, loading: loading)
        }
    }
}
