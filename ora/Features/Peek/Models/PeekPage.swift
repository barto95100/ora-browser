import AppKit
import Foundation

/// A link previewed over the current page (Peek, like Arc): its own page, in
/// the space and privacy mode of the tab it comes from, until it is closed or
/// opened as a tab (the page then moves to the tab as it is).
final class PeekPage: ObservableObject, Identifiable {
    let id = UUID()
    let page: BrowserPage
    let isPrivate: Bool
    /// The tab Peek was opened from.
    let openerTabID: UUID
    @Published private(set) var url: URL
    @Published private(set) var title: String = ""
    @Published private(set) var isLoading = true
    /// The page went to a tab: Peek must no longer show it (its view, still
    /// fading out, would take the page back from the tab).
    @Published private(set) var isMovedToTab = false
    private let pageDelegate: PeekPageDelegate

    init(page: BrowserPage, url: URL, opener: Tab) {
        self.page = page
        self.url = url
        isPrivate = opener.isPrivate
        openerTabID = opener.id
        pageDelegate = PeekPageDelegate(opener: opener)
        pageDelegate.peek = self
        page.delegate = pageDelegate
        page.load(URLRequest(url: url))
    }

    func moveToTab() {
        isMovedToTab = true
    }

    fileprivate func update(url: URL?) {
        if let url, url != self.url { self.url = url }
    }

    fileprivate func update(title: String?) {
        let title = title ?? ""
        if title != self.title { self.title = title }
    }

    fileprivate func update(isLoading: Bool) {
        if isLoading != self.isLoading { self.isLoading = isLoading }
    }
}

/// Follows the Peek page; links it opens in new windows become tabs.
private final class PeekPageDelegate: BrowserPageDelegate {
    weak var peek: PeekPage?
    private weak var opener: Tab?

    init(opener: Tab) {
        self.opener = opener
    }

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        // ⌘-click: a background tab, like in a tab.
        guard navigationAction.modifierFlags.contains(.command), let url = navigationAction.request.url else {
            return .allow
        }
        openTab(url, inFront: navigationAction.modifierFlags.contains(.shift))
        return .cancel
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL) {
        openTab(url, inFront: true)
    }

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {
        peek?.update(url: url)
    }

    func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {
        peek?.update(title: title)
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        peek?.update(isLoading: event.isLoading)
    }

    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {
        MainActor.assumeIsolated {
            opener?.downloadManager?.handleDownload(download)
        }
    }

    private func openTab(_ url: URL, inFront: Bool) {
        guard let opener, let tabManager = opener.tabManager else { return }
        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: opener.historyManager ?? tabManager.historyManager,
                downloadManager: opener.downloadManager,
                focusAfterOpening: inFront,
                isPrivate: opener.isPrivate,
                loadSilently: !inFront
            )
        }
    }
}
