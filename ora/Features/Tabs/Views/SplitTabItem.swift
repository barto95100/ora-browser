import SwiftUI

/// Sidebar row of a split, like Arc: both tabs side by side in one row. A
/// click on one side focuses it.
struct SplitTabItem: View {
    let left: Tab
    let right: Tab
    let isDragging: Bool
    let onSelect: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onHoverTab: (Tab, Bool) -> Void
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var hoveredTabID: UUID?
    @State private var rowWidth: CGFloat = 0

    private var isSelected: Bool {
        tabManager.isActive(left) || tabManager.isActive(right)
    }

    /// The side under the mouse, which the context menu acts on.
    private var menuTab: Tab {
        hoveredTabID == right.id ? right : left
    }

    var body: some View {
        HStack(spacing: 4) {
            side(left)
            Rectangle()
                .fill(theme.foreground.opacity(0.15))
                .frame(width: 1, height: 16)
            side(right)
        }
        .padding(4)
        .opacity(isDragging ? 0.0 : 1.0)
        .background(rowBackground, in: .rect(cornerRadius: 10))
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in rowWidth = width }
            }
        }
        .overlay(
            isDragging ?
                ConditionallyConcentricRectangle(cornerRadius: 10)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                : nil
        )
        .contentShape(ConditionallyConcentricRectangle(cornerRadius: 10))
        // One gesture for the whole row, like a tab row: gestures on each side
        // kept the row from being dragged.
        .onTapGesture { location in
            onSelect(location.x < rowWidth / 2 ? left : right)
        }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        .geometryGroup()
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        let tab = menuTab
        Button {
            onPinToggle(tab)
        } label: {
            Label("Pin Tab", systemImage: "pin")
        }

        Button {
            onFavoriteToggle(tab)
        } label: {
            Label("Add to Favorites", systemImage: "star")
        }

        Divider()

        Button {
            tabManager.separateSplit(containing: left)
        } label: {
            Label("Separate Tabs", systemImage: "rectangle.split.2x1.slash")
        }

        Divider()

        Button(role: .destructive) {
            onClose(tab)
        } label: {
            Label("Close Tab", systemImage: "xmark")
        }

        Button(role: .destructive) {
            onClose(right)
            onClose(left)
        } label: {
            Label("Close Both Tabs", systemImage: "xmark")
        }
    }

    private func side(_ tab: Tab) -> some View {
        let isFocused = tabManager.isActive(tab)
        let textColor = isFocused ? Color.white : theme.foreground
        return HStack(spacing: 6) {
            FavIcon(
                isWebViewReady: tab.isWebViewReady,
                favicon: tab.favicon,
                faviconLocalFile: tab.faviconLocalFile,
                textColor: textColor,
                isPlayingMedia: tab.isPlayingMedia,
                mediaCaptureState: tab.mediaCaptureState
            )
            Text(tab.title)
                .font(.system(size: 13))
                .foregroundColor(textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hoveredTabID == tab.id {
                ActionButton(icon: "xmark", color: textColor) { onClose(tab) }
                    .help("Close Tab")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(isFocused ? theme.activeTabBackground : .clear, in: .rect(cornerRadius: 7))
        .onHover { hovering in
            if hovering {
                hoveredTabID = tab.id
            } else if hoveredTabID == tab.id {
                hoveredTabID = nil
            }
            onHoverTab(tab, hovering)
        }
    }

    private var rowBackground: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isSelected || isHovering {
            return theme.activeTabBackground.opacity(colorScheme == .dark ? 0.3 : 0.1)
        }
        return .clear
    }
}
