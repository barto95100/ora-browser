import AppKit
import SwiftUI

/// Drop on a folder of the pinned section: a tab goes in it (last), a folder
/// takes its place.
struct FolderDropDelegate: DropDelegate {
    let folder: Folder
    @Binding var draggedItem: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedItem, draggedID != folder.id else { return }
        let container = folder.container
        if let moved = container.tabs.first(where: { $0.id == draggedID }) {
            guard container.folder(of: moved)?.id != folder.id else { return }
            performHapticFeedback(pattern: .alignment)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                container.addTab(moved, to: folder)
                folder.isOpened = true
            }
        } else if let movedFolder = container.folders.first(where: { $0.id == draggedID }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                container.moveFolder(movedFolder, onto: folder.id)
            }
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
        folder.container.modelContext?.saveOrLog("drop on folder")
        return true
    }
}
