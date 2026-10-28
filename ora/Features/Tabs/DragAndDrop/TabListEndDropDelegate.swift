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
        .init(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        try? container.modelContext?.save()
        return true
    }
}
