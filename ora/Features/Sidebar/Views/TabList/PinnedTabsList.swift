import SwiftData
import SwiftUI

struct PinnedTabsList: View {
    /// The space, whose pinned section also holds folders.
    let container: TabContainer
    let tabs: [Tab]
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void
    let onMoveToContainer: (Tab, TabContainer) -> Void
    let containers: [TabContainer]
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: 8) {
            Text("Pinned")
                .font(.callout)
                .foregroundColor(theme.mutedForeground)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        tabManager.createFolder(in: container)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
            let entries = container.pinnedEntries
            if entries.isEmpty {
                EmptyPinnedTabs()
            } else {
                ForEach(entries) { entry in
                    switch entry {
                    case let .tab(tab):
                        tabRow(tab)
                    case let .folder(folder):
                        folderRows(folder)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(
            of: [.text],
            delegate: SectionDropDelegate(
                items: tabs,
                draggedItem: $draggedItem,
                targetSection: .pinned,
                tabManager: tabManager
            )
        )
    }

    private func tabRow(_ tab: Tab) -> some View {
        TabItem(
            tab: tab,
            isSelected: tabManager.isActive(tab),
            isDragging: draggedItem == tab.id,
            onTap: { onSelect(tab) },
            onPinToggle: { onPinToggle(tab) },
            onFavoriteToggle: { onFavoriteToggle(tab) },
            onClose: { onClose(tab) },
            onDuplicate: { onDuplicate(tab) },
            onMoveToContainer: { onMoveToContainer(tab, $0) },
            availableContainers: containers
        )
        .onDrag { onDrag(tab.id) }
        .onDrop(
            of: [.text],
            delegate: TabDropDelegate(
                item: tab,
                draggedItem: $draggedItem,
                targetSection: .pinned
            )
        )
    }

    /// A folder and, below it, its tabs: all when it is open, only the active
    /// tab when it is closed (like Arc). Hidden while the folder is dragged.
    private func folderRows(_ folder: Folder) -> some View {
        VStack(spacing: 8) {
            FolderItem(folder: folder, isDragging: draggedItem == folder.id)
                .onDrag { onDrag(folder.id) }
                .onDrop(
                    of: [.text],
                    delegate: FolderDropDelegate(folder: folder, draggedItem: $draggedItem)
                )
            if draggedItem != folder.id {
                let shownTabs = container.tabs(in: folder).filter { folder.isOpened || tabManager.isActive($0) }
                if !shownTabs.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(shownTabs) { tab in
                            tabRow(tab)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    // Indented under the folder, like Arc.
                    .padding(.leading, 16)
                }
            }
        }
    }
}
