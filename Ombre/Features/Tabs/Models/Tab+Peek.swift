import Foundation

extension Tab {
    /// Previews a link over this tab (Peek), in this tab's space.
    func openPeek(_ url: URL) {
        guard let tabManager else { return }
        MainActor.assumeIsolated {
            tabManager.closePeek()
            tabManager.peek = PeekPage(page: makeBrowserPage(isPrivate: isPrivate), url: url, opener: self)
        }
    }

    /// Takes over a page that is already loaded (a Peek opened as a tab):
    /// nothing is reloaded, the page keeps its state.
    func adopt(
        _ page: BrowserPage,
        historyManager: HistoryManager,
        downloadManager: DownloadManager,
        tabManager: TabManager,
        recordsVisit: Bool = true
    ) {
        // First: the page is kept in the window's runtime.
        self.tabManager = tabManager
        if passwordCoordinator == nil {
            passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        }
        browserPage = page
        self.historyManager = historyManager
        self.downloadManager = downloadManager
        setupBrowserPageDelegate(for: page)
        syncBackgroundColorFromHex()
        isWebViewReady = true
        // A page WebKit is about to load is recorded once loaded.
        if recordsVisit { recordVisit() }
        WebExtensionsHub.tabOpened(self)
    }
}
