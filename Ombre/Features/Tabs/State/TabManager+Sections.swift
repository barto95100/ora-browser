import SwiftData
import SwiftUI

/// Where a tab sits: favorites, pinned or normal, its space, and ⌘1…⌘9.
extension TabManager {
    func togglePinTab(_ tab: Tab) {
        if tab.type == .pinned {
            // Back on top of the tabs, like Arc.
            tab.order = tab.container.topOrder(of: .normal)
            tab.type = .normal
            tab.savedURL = nil
            tab.folderID = nil
        } else {
            tab.type = .pinned
            tab.savedURL = tab.url
            tab.container.appendPinned(tab)
        }

        modelContext.saveOrLog("toggle pin tab")
    }

    func toggleFavTab(_ tab: Tab) {
        tab.folderID = nil
        if tab.type == .fav {
            tab.order = tab.container.topOrder(of: .normal)
            tab.type = .normal
            tab.savedURL = nil
        } else {
            tab.type = .fav
            tab.savedURL = tab.url
            tab.container.appendFavorite(tab)
        }

        modelContext.saveOrLog("toggle favorite tab")
    }

    /// The window stays in its space: moving the tab it shows shows the
    /// space's next tab. The tab goes where a new one would in its section.
    func moveTabToContainer(_ tab: Tab, toContainer: TabContainer) {
        guard tab.container.id != toContainer.id else { return }
        separateSplit(containing: tab, save: false)
        let wasActive = activeTab?.id == tab.id
        let fromContainer = tab.container
        // Taken before the move, without the tab.
        let topOrder = toContainer.topOrder(of: .normal)
        tab.folderID = nil
        tab.container = toContainer
        switch tab.type {
        case .pinned: toContainer.appendPinned(tab)
        case .fav: toContainer.appendFavorite(tab)
        case .normal: tab.order = topOrder
        }
        if wasActive {
            if let next = Self.lastUsedTab(in: fromContainer, except: tab) {
                activateTab(next)
            } else {
                activeTab?.maybeIsActive = false
                activeTab = nil
            }
        }
        modelContext.saveOrLog("move tab to space")
    }

    func selectTabAtIndex(_ index: Int) {
        guard let container = activeContainer else { return }

        // Match the sidebar ordering: favorites, then pinned, then normal tabs
        // All sorted by order in descending order
        let favoriteTabs = container.tabs
            .filter { $0.type == .fav }
            .sorted(by: { $0.order > $1.order })

        // Tabs of closed folders are hidden.
        let pinnedTabs = container.visiblePinnedTabs(activeTabID: activeTab?.id)

        // The right side of a split of normal tabs shares its left side's row.
        let splitRightTabIDs = splitRows(in: container).hidden
        let normalTabs = container.tabs
            .filter { $0.type == .normal && !splitRightTabIDs.contains($0.id) }
            .sorted(by: { $0.order > $1.order })

        // Combine all tabs in the same order as the sidebar
        let allTabs = favoriteTabs + pinnedTabs + normalTabs

        // Handle special case: Command+9 selects the last tab
        let targetIndex = (index == 9) ? allTabs.count - 1 : index - 1

        // Validate index is within bounds
        guard targetIndex >= 0, targetIndex < allTabs.count else { return }

        let targetTab = allTabs[targetIndex]
        activateTab(targetTab)
    }
}
