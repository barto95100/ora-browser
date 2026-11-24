import AppKit
import SwiftUI

struct FavTabItem: View {
    let tab: Tab
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode

    @State private var isHovering = false

    /// The icon, `size` wide (see `FavoritesGridMetrics.iconSize`).
    @ViewBuilder
    private func favicon(size: CGFloat) -> some View {
        if tab.faviconLocalFile != nil {
            LocalFavIcon(
                faviconLocalFile: tab.faviconLocalFile,
                textColor: Color(.white),
                isGrayscale: !tab.isWebViewReady,
                size: size
            )
        } else if let favicon = tab.favicon, tab.isWebViewReady {
            AsyncImage(
                url: favicon
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } placeholder: {
                LocalFavIcon(
                    faviconLocalFile: tab.faviconLocalFile,
                    textColor: Color(.white),
                    size: size
                )
            }
        } else {
            LocalFavIcon(
                faviconLocalFile: tab.faviconLocalFile,
                textColor: Color(.white),
                size: size
            )
        }
    }

    /// The icon with its badges, centered in a cell `height` tall: they grow
    /// and shrink with it, the badges kept at the icon's corners.
    private func content(height: CGFloat) -> some View {
        let size = FavoritesGridMetrics.iconSize(forCellHeight: height)
        let offset = FavoritesGridMetrics.badgeOffset(forIconSize: size)
        return favicon(size: size)
            // Next to the icon, like the other tabs: in the corner of the
            // card it was cut by the rounded border.
            .overlay(alignment: .bottomTrailing) {
                if let badge = mediaBadge {
                    Image(systemName: badge.symbolName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 8, height: 8)
                        .foregroundColor(badge.color)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 12, height: 12)
                        )
                        .help(badge.help)
                        .offset(x: offset, y: offset)
                }
            }
            .overlay(alignment: .topTrailing) {
                AgentTabBadge(tabID: tab.id).offset(x: offset, y: -offset)
            }
    }

    /// Camera or microphone in use (red, grey when paused) before playing sound,
    /// like the other tabs.
    private var mediaBadge: MediaBadge? {
        let capture = tab.mediaCaptureState
        if let device = capture.indicatedDevice {
            let isPaused = capture[device] == .muted
            return MediaBadge(
                symbolName: device.symbolName(isPaused: isPaused),
                color: isPaused ? .white.opacity(0.9) : .red,
                help: isPaused ? String(localized: "Paused") : String(localized: "In use")
            )
        }
        if tab.isPlayingMedia {
            return MediaBadge(symbolName: "speaker.wave.2.fill", color: .white.opacity(0.9), help: "")
        }
        return nil
    }

    var body: some View {
        // The cell the grid gives (see `FavoritesGridLayout`), read in the
        // same layout pass: no jump while the sidebar is resized.
        GeometryReader { proxy in
            content(height: proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            if tabManager.isActive(tab) {
                tab
                    .restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        tabManager: tabManager,
                        isPrivate: privacyMode.isPrivate
                    )
            }
        }
        .foregroundColor(theme.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isDragging ? 0.0 : 1.0)
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(SelectionRing(isShown: tabManager.isInSelection(tab) && !isDragging))
        .overlay(
            isDragging
                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                : isSelected
                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor,
                    lineWidth: 1
                )
                : nil
        )
        .onTapGesture {
            guard tabManager.renamingTabID != tab.id else { return }
            // A ⌘- or ⇧-click selects: the tab isn't shown, its page not loaded.
            let isPlainClick = TabManager.SelectionClick(NSEvent.modifierFlags) == .plain
            onTap()
            if isPlainClick, !tab.isWebViewReady {
                tab
                    .restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        tabManager: tabManager,
                        isPrivate: privacyMode.isPrivate
                    )
            }
        }
        .onHover { isHovering = $0 }
        // A favorite shows only its icon: its name on hover.
        .help(tab.displayName)
        // Rename…: its name in a small field below it (see `TabNameText`).
        .popover(isPresented: isRenamingBinding, arrowEdge: .bottom) {
            TabNameText(tab: tab, font: .system(size: 13), style: AnyShapeStyle(.primary))
                .frame(width: 220)
                .padding(10)
                .environmentObject(tabManager)
        }
        .tabAccessibility(
            tab: tab,
            isSelected: isSelected,
            isInSelection: tabManager.isInSelection(tab),
            activate: onTap, actions: TabSelectionAccessibility.actions(
                for: tab,
                tabManager: tabManager
            ) + [
                (name: String(localized: "Close Tab"), action: onClose),
                (name: String(localized: "Remove from Favorites"), action: onFavoriteToggle),
                (name: String(localized: "Copy Address"), action: { TabAddresses.copy([tab]) })
            ]
        )
        .contextMenu {
            let menuTabs = tabManager.menuTabs(for: tab)
            if menuTabs.count > 1 {
                MultipleTabsMenu(tabs: menuTabs)
            } else {
                singleTabMenuItems
            }
        }
    }

    /// The rename popover closed from outside (a click elsewhere): the name
    /// typed is kept (see `TabNameText`), unless Escape.
    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { tabManager.renamingTabID == tab.id },
            set: { isShown in
                if !isShown, tabManager.renamingTabID == tab.id { tabManager.renamingTabID = nil }
            }
        )
    }

    private var singleTabMenuItems: some View {
        Group {
            Button(action: onFavoriteToggle) {
                Label("Remove from Favorites", systemImage: "star.slash")
            }

            Button(action: onDuplicate) {
                Label("Duplicate Tab", systemImage: "doc.on.doc")
            }

            TabRenameMenuItems(tab: tab)

            CopyTabAddressButton(tab: tab)

            Divider()

            Button(role: .destructive, action: onClose) {
                Label("Close Tab", systemImage: "xmark")
            }
        }
    }

    private var backgroundColor: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isSelected {
            return theme.invertedSolidWindowBackgroundColor.opacity(0.3)
        } else if tabManager.isInSelection(tab) {
            return theme.activeTabBackground.opacity(0.35)
        } else if isHovering {
            return theme.activeTabBackground.opacity(0.3)
        }
        return theme.mutedBackground
    }
}

private struct MediaBadge {
    let symbolName: String
    let color: Color
    let help: String
}
