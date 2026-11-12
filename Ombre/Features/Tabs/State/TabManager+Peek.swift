import Foundation

extension TabManager {
    func closePeek() {
        guard let peek else { return }
        self.peek = nil
        peek.close()
        peek.page.teardown()
    }

    /// "Open in New Tab" (⌘O): the Peek page becomes a regular tab, as it is.
    func openPeekInTab() {
        openPeekPage(inSplitView: false)
    }

    /// "Open in Split View": the Peek page becomes a regular tab, shown at the
    /// right of the tab it was opened from, like Arc.
    func openPeekInSplitView() {
        openPeekPage(inSplitView: true)
    }

    private func openPeekPage(inSplitView: Bool) {
        guard let peek, activeContainer != nil else { return }
        // Peek first lets go of the page; the tab takes it on the next pass.
        // Done at once, Peek's view (kept while it fades out) took it back.
        peek.moveToTab()
        DispatchQueue.main.async { [weak self] in
            self?.adoptPeekPage(peek, inSplitView: inSplitView)
        }
    }

    private func adoptPeekPage(_ peek: PeekPage, inSplitView: Bool) {
        guard self.peek === peek, let container = activeContainer else { return }
        self.peek = nil

        let placeholder = Self.initialTitleAndFavicon(for: peek.url)
        let tab = makeTab(
            url: peek.url,
            title: peek.title.isEmpty ? placeholder?.title ?? peek.url.absoluteString : peek.title,
            favicon: peek.isPrivate ? nil : placeholder?.favicon,
            in: container,
            isPrivate: peek.isPrivate,
            historyManager: historyManager,
            downloadManager: downloadManager
        )
        // For the extensions: no longer Peek, the tab (told by `adopt`).
        WebExtensionsHub.pageClosed(peek.page)
        tab.adopt(peek.page, historyManager: historyManager, downloadManager: downloadManager, tabManager: self)
        tab.updateMediaCaptureState(peek.page.mediaCaptureState)
        tab.openerURL = peek.openerURL
        // What the page blocked so far shows in the tab's shield.
        tab.blockedContent = peek.blockedContent
        // "Don't show more dialogs" chosen in Peek holds in the tab, until
        // the page loads a new document.
        tab.pageDelegate?.sheets.dialogPolicy = peek.sheets.dialogPolicy
        if inSplitView {
            // Beside the tab Peek was opened from.
            if let opener = container.tabs.first(where: { $0.id == peek.openerTabID }), activeTab?.id != opener.id {
                activateTab(opener)
            }
            openInSplitView(tab, on: .right)
        } else {
            activateTab(tab)
        }
        container.lastAccessedAt = Date()
        modelContext.saveOrLog("adopt peek page")
    }
}
