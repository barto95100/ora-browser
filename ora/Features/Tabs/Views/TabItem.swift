import AppKit
import SwiftUI

struct LocalFavIcon: View {
    let faviconLocalFile: URL?
    let textColor: Color
    /// Grey for tabs whose page is not loaded.
    var isGrayscale = true

    @State private var image: NSImage?

    @ViewBuilder
    private var icon: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .cornerRadius(4)
                .grayscale(isGrayscale ? 1.0 : 0.0)
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(textColor)
        }
    }

    var body: some View {
        icon
            // Reload when the tab's icon file changes (another site), instead of
            // keeping the first image loaded.
            .task(id: faviconLocalFile) {
                image = await Self.loadImage(at: faviconLocalFile)
            }
    }

    private static func loadImage(at url: URL?) async -> NSImage? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            NSImage(contentsOf: url)
        }.value
    }
}

struct FavIcon: View {
    let isWebViewReady: Bool
    let favicon: URL?
    let faviconLocalFile: URL?
    let textColor: Color
    var isPlayingMedia: Bool = false
    var mediaCaptureState = BrowserMediaCaptureState()

    /// Camera first: it matters more than the microphone.
    private var captureDevice: BrowserCaptureDevice? {
        BrowserCaptureDevice.allCases.first { mediaCaptureState[$0] != .none }
    }

    private var hasIndicator: Bool {
        isPlayingMedia || captureDevice != nil
    }

    var body: some View {
        HStack(spacing: 4) {
            if faviconLocalFile != nil {
                // The page's icon, downloaded once (see FaviconStore).
                LocalFavIcon(faviconLocalFile: faviconLocalFile, textColor: textColor, isGrayscale: !isWebViewReady)
            } else if let favicon, isWebViewReady {
                AsyncImage(
                    url: favicon
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } placeholder: {
                    LocalFavIcon(
                        faviconLocalFile: faviconLocalFile,
                        textColor: textColor
                    )
                }
            } else {
                LocalFavIcon(
                    faviconLocalFile: faviconLocalFile,
                    textColor: textColor
                )
            }

            if let captureDevice {
                let isPaused = mediaCaptureState[captureDevice] == .muted
                Image(systemName: captureDevice.symbolName(isPaused: isPaused))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .foregroundColor(isPaused ? textColor.opacity(0.8) : .red)
                    .help(isPaused ? "Paused" : "In use")
            } else if isPlayingMedia {
                Image(systemName: "speaker.wave.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .foregroundColor(textColor.opacity(0.8))
            }
        }
        .frame(width: hasIndicator ? 28 : 16, height: 16)
    }
}

struct TabItem: View {
    let tab: Tab
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onPinToggle: () -> Void
    let onFavoriteToggle: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onMoveToContainer: (TabContainer) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode
    let availableContainers: [TabContainer]

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack {
            FavIcon(
                isWebViewReady: tab.isWebViewReady,
                favicon: tab.favicon,
                faviconLocalFile: tab.faviconLocalFile,
                textColor: textColor,
                isPlayingMedia: tab.isPlayingMedia,
                mediaCaptureState: tab.mediaCaptureState
            )
            tabTitle
            Spacer()
            actionButton
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
        .onTapGesture {
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
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
        }
        .padding(8)
        .opacity(isDragging ? 0.0 : 1.0)
        .background(backgroundColor, in: .rect(cornerRadius: 10))
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
        .onTapGesture {
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
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
        }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuItems }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        .geometryGroup()
    }

    private var tabTitle: some View {
        Text(tab.title)
            .font(.system(size: 13))
            .foregroundColor(textColor)
            .lineLimit(1)
    }

    private var backgroundColor: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isSelected {
            return theme.activeTabBackground
        } else if isHovering {
            if colorScheme == .dark {
                return theme.activeTabBackground.opacity(0.3)
            } else {
                return theme.activeTabBackground.opacity(0.1)
            }
        }
        return .clear
    }

    private var textColor: Color {
        isSelected ? .white : theme.foreground
    }

    @ViewBuilder
    private var actionButton: some View {
        if isHovering, tab.type == .pinned, !tab.isWebViewReady {
            ActionButton(icon: "pin.slash", color: textColor, action: onPinToggle).help("Unpin Tab")
        } else if isHovering {
            ActionButton(icon: "xmark", color: textColor, action: onClose).help("Close Tab")
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: onPinToggle) {
            Label(
                tab.type == .pinned ? "Unpin Tab" : "Pin Tab",
                systemImage: tab.type == .pinned ? "pin.slash" : "pin"
            )
        }

        Button(action: onFavoriteToggle) {
            Label(
                tab.type == .fav ? "Remove from Favorites" : "Add to Favorites",
                systemImage: tab.type == .fav ? "star.slash" : "star"
            )
        }

        Button(action: onDuplicate) {
            Label("Duplicate Tab", systemImage: "doc.on.doc")
        }

        if tabManager.canOpenInSplitView(tab) {
            Button {
                tabManager.openInSplitView(tab)
            } label: {
                Label("Open in Split View", systemImage: "rectangle.split.2x1")
            }
        }

        Divider()

        if availableContainers.count > 1 {
            Divider()

            Menu("Move to Container") {
                ForEach(availableContainers) { container in
                    if tab.container.id != container.id {
                        Button(action: { onMoveToContainer(container) }) {
                            Text(container.emoji.isEmpty ? container.name : "\(container.emoji) \(container.name)")
                        }
                    }
                }
            }

            Divider()
        }

        Button(role: .destructive, action: onClose) {
            Label("Close Tab", systemImage: "xmark")
        }
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 12, height: 12)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
