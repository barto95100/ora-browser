import AppKit
import SwiftUI

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct TabDropDelegate: DropDelegate {
    let item: Tab  // to
    @Binding var draggedItem: UUID?

    let targetSection: TabSection

    func dropEntered(info: DropInfo) {
        // The dragged tab is known right away: reading it back from the drag
        // item was asynchronous, so the list lagged and fast moves could be
        // applied out of order.
        guard let draggedID = draggedItem, draggedID != item.id else { return }
        // A folder dragged over a pinned tab: to that tab's place, in its
        // folder if it is in one (folders hold folders).
        if let folder = item.container.folders.first(where: { $0.id == draggedID }) {
            guard item.type == .pinned else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                item.container.moveFolder(folder, onto: item.id)
            }
            return
        }
        guard let moved = item.container.tabs.first(where: { $0.id == draggedID }) else { return }

        performHapticFeedback(pattern: .alignment)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            item.container.moveTab(moved, onto: item)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggedItem == nil ? .copy : .move)
    }

    /// A tab being dragged, or files from the Finder: they open as tabs, as
    /// on the rest of the window (see `FileDrop`).
    func validateDrop(info: DropInfo) -> Bool {
        draggedItem != nil || FileDrop.hasOpenableFiles()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedItem != nil else { return FileDrop.open(info, in: nil) }
        draggedItem = nil
        item.container.modelContext?.saveOrLog("drop on tab")
        return true
    }
}
