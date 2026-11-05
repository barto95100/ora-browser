import SwiftData
import SwiftUI

/// Where a tab sits: favorites, pinned or normal, its space, and ⌘1…⌘9.
extension TabManager {
    func togglePinTab(_ tab: Tab) {
        if tab.type == .pinned {
            tab.type = .normal
            tab.savedURL = nil
            tab.folderID = nil
        } else {
            tab.type = .pinned
            tab.savedURL = tab.url
        }

        modelContext.saveOrLog("toggle pin tab")
    }

    func toggleFavTab(_ tab: Tab) {
        tab.folderID = nil
        if tab.type == .fav {
            tab.type = .normal
            tab.savedURL = nil
        } else {
            tab.type = .fav
            tab.savedURL = tab.url
        }

        modelContext.saveOrLog("toggle favorite tab")
    }

    func moveTabToContainer(_ tab: Tab, toContainer: TabContainer) {
        separateSplit(containing: tab, save: false)
        tab.folderID = nil
        tab.container = toContainer
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
