import AppKit
import SwiftUI

/// Drop in the empty space under the last tab: the tab goes last, like in
/// Arc (dropped on the last tab, a tab from another section went before it).
struct TabListEndDropDelegate: DropDelegate {
    let container: TabContainer
    @Binding var draggedItem: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedItem,
              let moved = container.tabs.first(where: { $0.id == draggedID })
        else { return }
        performHapticFeedback(pattern: .alignment)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            container.moveToEndOfNormalTabs(moved)
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
        container.modelContext?.saveOrLog("drop at end of tab list")
        return true
    }
}
