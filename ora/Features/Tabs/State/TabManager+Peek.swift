import Foundation

extension TabManager {
    func closePeek() {
        guard let peek else { return }
        self.peek = nil
        peek.page.teardown()
    }

    /// "Open in New Tab" (⌘O): the Peek page becomes a regular tab, as it is.
    func openPeekInTab() {
        guard let peek, activeContainer != nil else { return }
        // Peek first lets go of the page; the tab takes it on the next pass.
        // Done at once, Peek's view (kept while it fades out) took it back.
        peek.moveToTab()
        DispatchQueue.main.async { [weak self] in
            self?.adoptPeekPage(peek)
        }
    }

    private func adoptPeekPage(_ peek: PeekPage) {
        guard self.peek === peek, let container = activeContainer else { return }
        self.peek = nil

        let placeholder = Self.initialTitleAndFavicon(for: peek.url)
        let tab = Tab(
            url: peek.url,
            title: peek.title.isEmpty ? placeholder?.title ?? peek.url.absoluteString : peek.title,
            favicon: placeholder?.favicon,
            container: container,
            type: .normal,
            isPlayingMedia: false,
            order: container.tabs.count + 1,
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            isPrivate: peek.isPrivate
        )
        modelContext.insert(tab)
        container.tabs.append(tab)
        tab.adopt(peek.page, historyManager: historyManager, downloadManager: downloadManager, tabManager: self)
        activateTab(tab)
        container.lastAccessedAt = Date()
        try? modelContext.save()
    }
}
