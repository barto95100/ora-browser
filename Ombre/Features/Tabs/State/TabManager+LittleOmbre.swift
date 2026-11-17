import Foundation
import SwiftData
@preconcurrency import WebKit

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

    /// A page Little Ombre's page opens in a new window (`target="_blank"`,
    /// `window.open` without a size, ⌘-click): a tab of Little Ombre's space
    /// in this window, as a tab's link would. With `configuration`, linked
    /// to its opener (`window.opener`, sign-in pages); else loading `url`.
    /// None when the space is gone or the window's privacy differs.
    @discardableResult
    func openLittleOmbreLink(
        _ url: URL?,
        from popup: PopupPage,
        configuration: WKWebViewConfiguration?,
        disposition: BrowserNewTabDisposition
    ) -> Tab? {
        let spaceID = popup.context.spaceID
        let isPrivate = popup.context.isPrivate
        guard isPrivate == isPrivateWindow,
              let container = try? modelContext.fetch(FetchDescriptor<TabContainer>(
                  predicate: #Predicate { $0.id == spaceID }
              )).first
        else { return nil }
        let address = url ?? URL(string: "about:blank")!
        let placeholder = Self.initialTitleAndFavicon(for: address)
        let tab = makeTab(
            url: address,
            title: placeholder?.title ?? address.absoluteString,
            favicon: isPrivate ? nil : placeholder?.favicon,
            in: container,
            isPrivate: isPrivate,
            historyManager: historyManager,
            downloadManager: downloadManager
        )
        if let configuration {
            // WebKit loads it.
            let page = tab.makeLinkedBrowserPage(configuration: configuration, opener: popup.page)
            tab.adopt(
                page,
                historyManager: historyManager,
                downloadManager: downloadManager,
                tabManager: self,
                recordsVisit: false
            )
        } else {
            tab.restoreTransientState(
                historyManager: historyManager,
                downloadManager: downloadManager,
                tabManager: self,
                isPrivate: isPrivate
            )
        }
        // Little Ombre has no split view: a tab in front instead.
        if disposition != .background {
            if activeContainer?.id != container.id {
                activateContainer(container, activateLastAccessedTab: false)
            }
            activateTab(tab)
        }
        container.lastAccessedAt = Date()
        modelContext.saveOrLog("open Little Ombre link")
        tab.openerURL = popup.shownURL
        return tab
    }
}
