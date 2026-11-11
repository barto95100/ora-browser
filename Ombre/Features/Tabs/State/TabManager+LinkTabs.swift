import Foundation
@preconcurrency import WebKit

/// Tabs opened from a link of another tab (⌘-click, context menu, links
/// opening a new page).
extension TabManager {
    /// A tab for a window `opener`'s page opens (`window.open(url)`, a
    /// `target="_blank"` link), linked to it like in Safari: its page uses
    /// WebKit's `configuration`, so `window.opener` and `postMessage` work
    /// (sign-in, payments). Returns its web view, which WebKit then loads.
    /// `openerURL`: the page the link is on, if not the opener tab's (a popup).
    func openLinkedTab(
        url: URL?,
        from opener: Tab,
        configuration: WKWebViewConfiguration,
        disposition: BrowserNewTabDisposition,
        openerURL: URL? = nil
    ) -> WKWebView? {
        // In its opener's space: the page shares that space's data.
        guard let container = opener.parentContainer else { return nil }
        // swiftlint:disable:next force_unwrapping
        let address = url ?? URL(string: "about:blank")!
        let placeholder = Self.initialTitleAndFavicon(for: address)
        let tab = makeTab(
            url: address,
            title: placeholder?.title ?? address.absoluteString,
            favicon: opener.isPrivate ? nil : placeholder?.favicon,
            in: container,
            isPrivate: opener.isPrivate,
            historyManager: opener.historyManager ?? historyManager,
            downloadManager: opener.downloadManager ?? downloadManager
        )
        let page = tab.makeLinkedBrowserPage(configuration: configuration, opener: opener.browserPage)
        tab.adopt(
            page,
            historyManager: opener.historyManager ?? historyManager,
            downloadManager: opener.downloadManager ?? downloadManager,
            tabManager: self,
            recordsVisit: false
        )
        if opener.type == .normal {
            container.placeTab(tab, after: opener)
        }
        switch disposition {
        case .foreground:
            completePendingSplit(with: tab)
            activateTab(tab)
        case .splitView where activeTab?.id == opener.id:
            openInSplitView(tab)
        default:
            break
        }
        container.lastAccessedAt = Date()
        modelContext.saveOrLog("open linked tab")
        tab.openerURL = openerURL ?? opener.shownURL
        return page.webView
    }

    /// Opens `url` in a new tab right below the tab it comes from (at the top
    /// for a pinned or favorite tab), in front, in the background, or beside
    /// it in Split View.
    @discardableResult
    func openLinkTab(
        _ url: URL,
        from opener: Tab,
        disposition: BrowserNewTabDisposition,
        openerURL: URL? = nil
    ) -> Tab? {
        let inFront = disposition == .foreground
        guard let newTab = openTab(
            url: url,
            historyManager: opener.historyManager ?? historyManager,
            downloadManager: opener.downloadManager ?? downloadManager,
            focusAfterOpening: inFront,
            isPrivate: opener.isPrivate,
            loadSilently: !inFront
        ) else { return nil }
        newTab.openerURL = openerURL ?? opener.shownURL

        if opener.type == .normal, newTab.container.id == opener.container.id {
            opener.container.placeTab(newTab, after: opener)
            modelContext.saveOrLog("open link tab")
        }
        if disposition == .splitView, activeTab?.id == opener.id {
            openInSplitView(newTab)
        }
        return newTab
    }
}

@MainActor
extension Tab {
    /// The page the tab shows, for the tabs its links open: before it shows
    /// one, the page whose link opened it.
    var shownURL: URL {
        browserPage?.lastCommittedURL ?? openerURL ?? url
    }
}
