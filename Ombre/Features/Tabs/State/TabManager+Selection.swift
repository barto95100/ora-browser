import AppKit
import Foundation

/// Several tabs selected in the sidebar, like Arc: ⌘-click adds or removes a
/// tab, ⇧-click selects a range, a plain click or Escape ends it. The
/// selection stays in one space; its tabs are acted on together from their
/// context menu.
extension TabManager {
    /// What a click on a tab of the sidebar does to the selection.
    enum SelectionClick: Equatable {
        /// Shows the tab, and ends the selection.
        case plain
        /// ⌘: adds or removes the tab.
        case toggle
        /// ⇧: selects from the last tab ⌘-clicked (or the active one) to it.
        case range

        init(_ flags: NSEvent.ModifierFlags) {
            if flags.contains(.shift) {
                self = .range
            } else if flags.contains(.command) {
                self = .toggle
            } else {
                self = .plain
            }
        }
    }

    /// The tabs of `container` as the sidebar shows them, top to bottom:
    /// favorites, pinned tabs (a closed folder shows only the active tab in
    /// it), then the other tabs, a split row's two tabs together.
    func sidebarOrder(in container: TabContainer) -> [Tab] {
        let sorted = container.tabs.sorted { $0.order > $1.order }
        var order = sorted.filter { $0.type == .fav }
        appendPinned(container.pinnedEntries, of: container, to: &order)
        let splits = splitRows(in: container)
        for tab in sorted where tab.type == .normal && !splits.hidden.contains(tab.id) {
            if let split = splits.rows[tab.id] {
                order += [split.left, split.right]
            } else {
                order.append(tab)
            }
        }
        // A split's other side may be in another section: listed once.
        var seen = Set<UUID>()
        return order.filter { seen.insert($0.id).inserted }
    }

    private func appendPinned(_ entries: [PinnedEntry], of container: TabContainer, to order: inout [Tab]) {
        for entry in entries {
            switch entry {
            case let .tab(tab):
                order.append(tab)
            case let .folder(folder) where folder.isOpened:
                appendPinned(container.entries(in: folder), of: container, to: &order)
            case let .folder(folder):
                if let active = activeTab, container.contains(active, in: folder) { order.append(active) }
            }
        }
    }

    /// A click on a tab of the sidebar. Returns true when it changed the
    /// selection: the tab is then not shown.
    @discardableResult
    func handleSidebarClick(on tab: Tab, _ click: SelectionClick) -> Bool {
        // Another space's tabs never join the selection.
        if let first = selectedTabs.first, first.container.id != tab.container.id {
            clearTabSelection()
        }
        switch click {
        case .plain:
            if !selectedTabIDs.isEmpty { clearTabSelection() }
            return false
        case .toggle:
            var selection = selectedTabIDs
            // The tab shown counts as selected, like Arc.
            if selection.isEmpty, let active = activeTab, active.container.id == tab.container.id {
                selection.insert(active.id)
            }
            if selection.contains(tab.id) {
                selection.remove(tab.id)
            } else {
                selection.insert(tab.id)
            }
            selectedTabIDs = selection
            selectionAnchorID = tab.id
            return true
        case .range:
            let order = sidebarOrder(in: tab.container)
            let anchorID = selectionAnchorID ?? activeTab?.id
            guard let end = order.firstIndex(where: { $0.id == tab.id }) else { return false }
            let start = order.firstIndex { $0.id == anchorID } ?? end
            selectedTabIDs = Set(order[min(start, end) ... max(start, end)].map(\.id))
            if selectionAnchorID == nil { selectionAnchorID = order[start].id }
            return true
        }
    }

    /// The selected tabs, in the sidebar's order.
    var selectedTabs: [Tab] {
        guard !selectedTabIDs.isEmpty, let container = activeContainer else { return [] }
        let shown = sidebarOrder(in: container).filter { selectedTabIDs.contains($0.id) }
        let shownIDs = Set(shown.map(\.id))
        // Selected, but no longer shown (in a folder closed since): last.
        let hidden = container.tabs.filter { selectedTabIDs.contains($0.id) && !shownIDs.contains($0.id) }
        return shown + hidden
    }

    func isInSelection(_ tab: Tab) -> Bool {
        selectedTabIDs.contains(tab.id)
    }

    /// The tabs a context menu on `tab` acts on: the selection if `tab` is in
    /// it with others, else `tab` alone.
    func menuTabs(for tab: Tab) -> [Tab] {
        let selection = selectedTabs
        return selection.count > 1 && selection.contains(where: { $0.id == tab.id }) ? selection : [tab]
    }

    func clearTabSelection() {
        selectedTabIDs = []
        selectionAnchorID = nil
    }

    /// Adds `tab` to the selection, or takes it out (VoiceOver's actions,
    /// as a ⌘-click).
    func toggleSelection(of tab: Tab) {
        handleSidebarClick(on: tab, .toggle)
    }

    // MARK: - Actions on several tabs

    func closeTabs(_ tabs: [Tab]) {
        clearTabSelection()
        for tab in tabs {
            closeTab(tab: tab)
        }
    }

    /// Pins them all (`true`), or unpins them all, in the sidebar's order.
    func setPinned(_ tabs: [Tab], _ pinned: Bool) {
        clearTabSelection()
        for tab in tabs where (tab.type == .pinned) != pinned {
            togglePinTab(tab)
        }
    }

    func moveTabs(_ tabs: [Tab], to container: TabContainer) {
        clearTabSelection()
        for tab in tabs {
            moveTabToContainer(tab, toContainer: container)
        }
    }

    /// Into a folder of the pinned section: the tabs not pinned are pinned
    /// first, as a folder holds pinned tabs only.
    func moveTabs(_ tabs: [Tab], toFolder folder: Folder) {
        clearTabSelection()
        for tab in tabs {
            if tab.type != .pinned { togglePinTab(tab) }
            moveTab(tab, toFolder: folder)
        }
    }

    /// Two tabs of one space, side by side (the first one on the left).
    func canOpenInSplitView(_ tabs: [Tab]) -> Bool {
        guard tabs.count == 2 else { return false }
        return tabs[0].container.id == tabs[1].container.id
    }

    func openInSplitView(_ tabs: [Tab]) {
        guard canOpenInSplitView(tabs) else { return }
        clearTabSelection()
        openInSplitView(left: tabs[0], right: tabs[1])
    }
}
