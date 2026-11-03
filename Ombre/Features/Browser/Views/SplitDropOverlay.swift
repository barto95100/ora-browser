import SwiftUI

/// Shown over the page while a tab is dragged from the sidebar, like Arc: a
/// tab dropped on the left or right half opens beside the active tab, on that
/// side.
struct SplitDropOverlay: View {
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var side: SplitDropSide?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: side == .left ? .leading : .trailing) {
                Color.clear
                if side != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accent.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(theme.accent.opacity(0.7), lineWidth: 2)
                        )
                        .frame(width: max(geometry.size.width / 2 - 12, 0))
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: SplitDropDelegate(width: geometry.size.width, side: $side, tabManager: tabManager)
            )
        }
        .animation(.easeOut(duration: 0.15), value: side)
    }
}

private struct SplitDropDelegate: DropDelegate {
    let width: CGFloat
    @Binding var side: SplitDropSide?
    let tabManager: TabManager

    /// The dragged tab, unless it is the active one (a folder is not a tab).
    private var draggedTab: Tab? {
        guard let id = tabManager.draggingTabID, let active = tabManager.activeTab, id != active.id else {
            return nil
        }
        return active.container.tabs.first { $0.id == id }
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTab != nil
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        side = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let tab = draggedTab, let droppedSide = side else { return false }
        side = nil
        withAnimation(.easeOut(duration: 0.2)) {
            tabManager.openInSplitView(tab, on: droppedSide)
        }
        return true
    }

    private func update(_ info: DropInfo) {
        let newSide: SplitDropSide? = draggedTab == nil ? nil : (info.location.x < width / 2 ? .left : .right)
        if newSide != side {
            side = newSide
        }
    }
}
