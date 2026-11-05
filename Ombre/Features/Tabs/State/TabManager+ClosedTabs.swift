import Foundation
import SwiftData

/// A closed tab, kept to reopen it (⌘Z, like Arc and Safari).
struct ClosedTabSnapshot {
    let id: UUID
    let containerID: UUID
    let url: URL
    let savedURL: URL?
    let title: String
    let favicon: URL?
    let faviconLocalFile: URL?
    let createdAt: Date
    let lastAccessedAt: Date?
    let type: TabType
    let order: Int
    let backgroundColorHex: String
    let isPrivate: Bool

    init(tab: Tab) {
        id = tab.id
        containerID = tab.container.id
        url = tab.url
        savedURL = tab.savedURL
        title = tab.title
        favicon = tab.favicon
        faviconLocalFile = tab.faviconLocalFile
        createdAt = tab.createdAt
        lastAccessedAt = tab.lastAccessedAt
        type = tab.type
        order = tab.order
        backgroundColorHex = tab.backgroundColorHex
        isPrivate = tab.isPrivate
    }
}

extension TabManager {
    func restoreLastTab() {
        guard let snapshot = recentlyClosedTabs.popLast() else { return }
        // Still being closed (its media is stopping): ⌘Z cancels the close.
        // A new tab would share its id, which is unique.
        if let closing = closingTab(id: snapshot.id) {
            closing.isClosing = false
            activateTab(closing)
            return
        }
        let container = fetchContainers()
            .first(where: { $0.id == snapshot.containerID }) ?? activeContainer ?? createContainer()

        shiftRestoredTabOrders(in: container, restoring: snapshot)

        let restoredTab = makeTab(
            id: snapshot.id,
            url: snapshot.url,
            title: snapshot.title,
            favicon: snapshot.favicon,
            type: snapshot.type,
            order: snapshot.order,
            in: container,
            isPrivate: snapshot.isPrivate
        )
        restoredTab.savedURL = snapshot.savedURL
        restoredTab.faviconLocalFile = snapshot.faviconLocalFile
        restoredTab.createdAt = snapshot.createdAt
        restoredTab.lastAccessedAt = snapshot.lastAccessedAt
        restoredTab.backgroundColorHex = snapshot.backgroundColorHex
        activateTab(restoredTab)
        modelContext.saveOrLog("restore last tab")
    }

    func trackRecentlyClosedTab(_ tab: Tab) {
        recentlyClosedTabs.append(ClosedTabSnapshot(tab: tab))
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - maxRecentlyClosedTabs)
        }

        // ⌘Z outside a text field reopens it, like Arc and Safari
        // ("Undo Close Tab"); text fields keep undoing typing first.
        windowUndoManager?.registerUndo(withTarget: self) { manager in
            MainActor.assumeIsolated {
                manager.restoreLastTab()
            }
        }
        windowUndoManager?.setActionName("Close Tab")
    }

    private func shiftRestoredTabOrders(in container: TabContainer, restoring snapshot: ClosedTabSnapshot) {
        for tab in container.tabs where tab.type == snapshot.type && tab.order >= snapshot.order {
            tab.order += 1
        }
    }

    func reloadCancelledClose(of tab: Tab) {
        guard tab.browserPage == nil else { return }
        tab.isWebViewReady = false
        if activeTab?.id == tab.id {
            activateTab(tab)
        }
    }

    func closingTab(id: UUID) -> Tab? {
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first { $0.isClosing }
    }
}
