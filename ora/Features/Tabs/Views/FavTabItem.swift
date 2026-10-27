import AppKit
import SwiftData
import SwiftUI

struct FavTabItem: View {
    let tab: Tab
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onMoveToContainer: (TabContainer) -> Void

    @Environment(\.theme) private var theme
    @Query var containers: [TabContainer]
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode

    @State private var isHovering = false

    @ViewBuilder
    private var favicon: some View {
        if tab.faviconLocalFile != nil {
            LocalFavIcon(
                faviconLocalFile: tab.faviconLocalFile,
                textColor: Color(.white),
                isGrayscale: !tab.isWebViewReady
            )
        } else if let favicon = tab.favicon, tab.isWebViewReady {
            AsyncImage(
                url: favicon
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } placeholder: {
                LocalFavIcon(
                    faviconLocalFile: tab.faviconLocalFile,
                    textColor: Color(.white)
                )
            }
        } else {
            LocalFavIcon(
                faviconLocalFile: tab.faviconLocalFile,
                textColor: Color(.white)
            )
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
                help: isPaused ? "Paused" : "In use"
            )
        }
        if tab.isPlayingMedia {
            return MediaBadge(symbolName: "speaker.wave.2.fill", color: .white.opacity(0.9), help: "")
        }
        return nil
    }

    var body: some View {
        ZStack {
            favicon
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
                            .offset(x: 7, y: 7)
                    }
                }
        }
        .onTapGesture {
            onTap()
            if !tab.isWebViewReady {
                tab
                    .restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        tabManager: tabManager,
                        isPrivate: privacyMode.isPrivate
                    )
            }
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
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .opacity(isDragging ? 0.0 : 1.0)
        .background(backgroundColor)
        .cornerRadius(10)
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
            onTap()
            if !tab.isWebViewReady {
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
        .contextMenu {
            Button(action: onFavoriteToggle) {
                Label("Remove from Favorites", systemImage: "star.slash")
            }

            Button(action: onDuplicate) {
                Label("Duplicate Tab", systemImage: "doc.on.doc")
            }

            // Divider()

            //      Menu("Move to Container") {
            //        ForEach(containers) { container in
            //            if container.id != tabManager.activeContainer?.id {
            //            Button(action: { onMoveToContainer(container) }) {
            //              Label(container.title, systemImage: container.icon)
            //            }
            //          }
            //        }
            //      }

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
