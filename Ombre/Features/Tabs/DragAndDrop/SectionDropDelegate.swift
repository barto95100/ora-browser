import AppKit
import SwiftUI

struct SectionDropDelegate: DropDelegate {
    let items: [Tab]
    @Binding var draggedItem: UUID?
    let targetSection: TabSection
    let tabManager: TabManager

    /// Drop on an empty section (no tab to drop onto): the tab joins it.
    func dropEntered(info: DropInfo) {
        guard items.isEmpty,
              let draggedID = draggedItem,
              let container = tabManager.activeContainer,
              let moved = container.tabs.first(where: { $0.id == draggedID })
        else { return }

        performHapticFeedback(pattern: .alignment)
        let newType = tabType(for: targetSection)
        moved.folderID = nil
        moved.type = newType
        // Pinned and favorite tabs come back to their saved URL.
        moved.savedURL = newType == .normal ? nil : moved.url
        moved.order = 1
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
        tabManager.modelContext.saveOrLog("drop on section")
        return true
    }
}
