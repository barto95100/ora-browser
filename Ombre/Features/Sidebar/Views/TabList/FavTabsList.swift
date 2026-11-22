import AppKit
import SwiftUI

struct FavTabsGrid: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    let tabs: [Tab]
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void

    var body: some View {
        Group {
            if tabs.isEmpty {
                EmptyFavTabItem()
                    .onDrop(
                        of: [.text, .fileURL],
                        delegate: SectionDropDelegate(
                            items: tabs,
                            draggedItem: $draggedItem,
                            targetSection: .fav,
                            tabManager: tabManager
                        )
                    )
            } else {
                // The columns and cell sizes follow the width the sidebar
                // gives, in the same layout pass: resizing it reflows the
                // grid live.
                FavoritesGridLayout {
                    ForEach(tabs) { tab in
                        FavTabItem(
                            tab: tab,
                            isSelected: tabManager.isActive(tab),
                            isDragging: draggedItem == tab.id,
                            onTap: { onSelect(tab) },
                            onFavoriteToggle: { onFavoriteToggle(tab) },
                            onClose: { onClose(tab) },
                            onDuplicate: { onDuplicate(tab) }
                        )
                        .onDrag { onDrag(tab.id) }
                        .onDrop(
                            of: [.text, .fileURL],
                            delegate: TabDropDelegate(
                                item: tab,
                                draggedItem: $draggedItem,
                                targetSection: .fav
                            )
                        )
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.1), value: tabs.count)
        .onDrop(
            of: [.text, .fileURL],
            delegate: SectionDropDelegate(
                items: tabs,
                draggedItem: $draggedItem,
                targetSection: .fav,
                tabManager: tabManager
            )
        )
    }
}

/// The favorites in rows of `FavoritesGridMetrics`' columns, each proposed its
/// cell.
struct FavoritesGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Self.width(of: proposal, count: subviews.count)
        return CGSize(width: width, height: FavoritesGridMetrics(width: width, count: subviews.count).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = FavoritesGridMetrics(width: bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let frame = metrics.frame(at: index)
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// The width given, or (none, or unlimited) a full row at the narrowest.
    private static func width(of proposal: ProposedViewSize, count: Int) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        let columns = CGFloat(min(max(1, count), FavoritesGridMetrics.maximumColumns))
        return columns * FavoritesGridMetrics.minimumCellWidth + (columns - 1) * FavoritesGridMetrics.spacing
    }
}
