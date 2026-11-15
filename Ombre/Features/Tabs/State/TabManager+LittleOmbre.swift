import Foundation

/// Little Ombre's page going to a tab of this window ("Open in Ombre", ⌘O).
extension TabManager {
    /// How Little Ombre's page goes to a space of this window: as it is when
    /// it already uses that space's data (and the window's privacy), loaded
    /// again there otherwise (another space has its own cookies and logins).
    enum LittleOmbreMove: Equatable {
        case adopt
        case reload
    }

    static func littleOmbreMove(
        pageSpaceID: UUID,
        pageIsPrivate: Bool,
        to spaceID: UUID,
        windowIsPrivate: Bool
    ) -> LittleOmbreMove {
        pageSpaceID == spaceID && pageIsPrivate == windowIsPrivate ? .adopt : .reload
    }

    /// Opens Little Ombre's `page` in a tab of `container`, shown. Returns
    /// whether the tab took the page itself (Little Ombre must then not tear
    /// it down).
    @discardableResult
    func openLittleOmbrePage(
        _ page: BrowserPage,
        url: URL,
        title: String,
        pageSpaceID: UUID,
        isPrivate: Bool,
        in container: TabContainer
    ) -> Bool {
        if activeContainer?.id != container.id {
            activateContainer(container, activateLastAccessedTab: false)
        }
        let move = Self.littleOmbreMove(
            pageSpaceID: pageSpaceID,
            pageIsPrivate: isPrivate,
            to: container.id,
            windowIsPrivate: isPrivateWindow
        )
        guard move == .adopt else {
            openTab(
                url: url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: isPrivateWindow
            )
            return false
        }
        let placeholder = Self.initialTitleAndFavicon(for: url)
        let tab = makeTab(
            url: url,
            title: title.isEmpty ? placeholder?.title ?? url.absoluteString : title,
            favicon: isPrivate ? nil : placeholder?.favicon,
            in: container,
            isPrivate: isPrivate,
            historyManager: historyManager,
            downloadManager: downloadManager
        )
        // For the extensions: no longer Little Ombre's, the tab's (told by `adopt`).
        WebExtensionsHub.pageClosed(page)
        // Already recorded by Little Ombre.
        tab.adopt(
            page,
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            recordsVisit: false
        )
        tab.updateMediaCaptureState(page.mediaCaptureState)
        activateTab(tab)
        container.lastAccessedAt = Date()
        modelContext.saveOrLog("adopt Little Ombre page")
        return true
    }
}
