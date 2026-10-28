import Foundation

/// Tabs opened from a link of another tab (⌘-click, context menu, links
/// opening a new page).
extension TabManager {
    /// Opens `url` in a new tab right below the tab it comes from (at the top
    /// for a pinned or favorite tab), in front, in the background, or beside
    /// it in Split View.
    @discardableResult
    func openLinkTab(_ url: URL, from opener: Tab, disposition: BrowserNewTabDisposition) -> Tab? {
        let inFront = disposition == .foreground
        guard let newTab = openTab(
            url: url,
            historyManager: opener.historyManager ?? historyManager,
            downloadManager: opener.downloadManager ?? downloadManager,
            focusAfterOpening: inFront,
            isPrivate: opener.isPrivate,
            loadSilently: !inFront
        ) else { return nil }

        if opener.type == .normal, newTab.container.id == opener.container.id {
            opener.container.placeTab(newTab, after: opener)
            try? modelContext.save()
        }
        if disposition == .splitView, activeTab?.id == opener.id {
            openInSplitView(newTab)
        }
        return newTab
    }
}
