import AppKit
import Foundation

/// What the rest of Ora tells the extensions, on any macOS: the calls do
/// nothing before macOS 15.4, where WebKit has no extensions. Called on the
/// main thread only (tabs, windows and pages live there).
enum WebExtensionsHub {
    static var isSupported: Bool {
        if #available(macOS 15.4, *) { return true }
        return false
    }

    /// At launch, before the first page: pages get the extension controller.
    static func start() {
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated { WebExtensionsManager.shared.start() }
        }
    }

    /// A normal browser window (private windows run no extensions).
    static func registerWindow(_ window: NSWindow, tabManager: TabManager) {
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated {
                WebExtensionsManager.shared.registerWindow(window, tabManager: tabManager)
            }
        }
    }

    static func activeTabChanged(in tabManager: TabManager) {
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated { WebExtensionsManager.shared.activeTabChanged(in: tabManager) }
        }
    }

    /// A tab got its page.
    static func tabOpened(_ tab: Tab) {
        guard !tab.isPrivate else { return }
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated { WebExtensionsManager.shared.tabOpened(tab) }
        }
    }

    /// A tab's page went away (closed, or unloaded).
    static func tabClosed(_ tab: Tab) {
        guard !tab.isPrivate else { return }
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated { WebExtensionsManager.shared.tabClosed(tab) }
        }
    }

    static func tabChanged(_ tab: Tab, url: Bool = false, title: Bool = false, loading: Bool = false) {
        guard !tab.isPrivate else { return }
        if #available(macOS 15.4, *) {
            MainActor.assumeIsolated {
                WebExtensionsManager.shared.tabChanged(tab, url: url, title: title, loading: loading)
            }
        }
    }
}
