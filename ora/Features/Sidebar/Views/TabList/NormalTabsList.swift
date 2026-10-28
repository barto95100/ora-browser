import SwiftData
import SwiftUI

struct NormalTabsList: View {
    let tabs: [Tab]
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void
    let onMoveToContainer:
        (
            Tab,
            TabContainer
        ) -> Void
    let onAddNewTab: () -> Void
    @Query var containers: [TabContainer]
    @EnvironmentObject var tabManager: TabManager
    @State private var previousTabIds: [UUID] = []
    /// Tab under the mouse, closed by a middle click like in every browser.
    @State private var hoveredTab: Tab?
    @State private var middleClick = MiddleClickMonitor()

    var body: some View {
        VStack(spacing: 8) {
            NewTabButton(addNewTab: onAddNewTab)
            // A split shows as one row (see `TabManager.splitRows(in:)`).
            let splits = tabs.first.map { tabManager.splitRows(in: $0.container) }
            let hiddenTabIDs = splits?.hidden ?? []
            ForEach(tabs.filter { !hiddenTabIDs.contains($0.id) }) { tab in
                let split = splits?.rows[tab.id]
                row(for: tab, split: split)
                    .onDrag { onDrag(tab.id) }
                    .onDrop(
                        of: [.text],
                        delegate: TabDropDelegate(
                            item: tab,
                            draggedItem: $draggedItem,
                            targetSection: .normal
                        )
                    )
                    // A hidden sidebar (floating) reports no hover end.
                    .onDisappear {
                        if hoveredTab === tab || hoveredTab === split?.left || hoveredTab === split?.right {
                            hoveredTab = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldAnimate(tab))
            }
        }
        .onDrop(
            of: [.text],
            delegate: SectionDropDelegate(
                items: tabs,
                draggedItem: $draggedItem,
                targetSection: .normal,
                tabManager: tabManager
            )
        )
        .onAppear {
            previousTabIds = tabs.map(\.id)
            middleClick.start { closeHoveredTab() }
        }
        .onDisappear { middleClick.stop() }
        .onChange(of: tabs.map(\.id)) { _, newTabIds in
            previousTabIds = newTabIds
        }
    }

    @ViewBuilder
    private func row(for tab: Tab, split: (left: Tab, right: Tab)?) -> some View {
        if let split {
            SplitTabItem(
                left: split.left,
                right: split.right,
                isDragging: draggedItem == tab.id,
                onSelect: onSelect,
                onClose: onClose,
                onPinToggle: onPinToggle,
                onFavoriteToggle: onFavoriteToggle,
                onHoverTab: updateHover
            )
        } else {
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
            .onHover { updateHover(tab, $0) }
        }
    }

    private func updateHover(_ tab: Tab, _ hovering: Bool) {
        if hovering {
            hoveredTab = tab
        } else if hoveredTab === tab {
            hoveredTab = nil
        }
    }

    /// Middle click on a tab: close it. Only regular tabs, so pinned and
    /// favorite ones are never closed by accident.
    private func closeHoveredTab() -> Bool {
        guard let tab = hoveredTab, tab.type == .normal else { return false }
        hoveredTab = nil
        onClose(tab)
        return true
    }

    private func shouldAnimate(_ tab: Tab) -> Bool {
        // Only animate if the tab's position has actually changed
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tab.id }),
              let previousIndex = previousTabIds.firstIndex(where: { $0 == tab.id })
        else {
            return true // Animate new tabs or tabs that were just created
        }
        return currentIndex != previousIndex
    }
}
