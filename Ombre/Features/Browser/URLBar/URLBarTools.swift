import SwiftUI

/// Address bar tools, at its right: downloads, the tab's note, the tasks and
/// the browsing time (with the address in the sidebar, they are one menu next
/// to the window buttons, see `SidebarHeader`).
struct URLBarTools: View {
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: 8) {
            DownloadsURLBarButton(foregroundColor: foregroundColor)
            TabNoteButton(foregroundColor: foregroundColor)
            TasksButton(foregroundColor: foregroundColor)
            TimeURLBarButton(foregroundColor: foregroundColor)
        }
    }
}

/// The downloads, with a ring filling as they go on; a click, or a new
/// download, shows the latest ones under it (`DownloadsPopover`).
struct DownloadsURLBarButton: View {
    let foregroundColor: Color
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.theme) private var theme
    @State private var isShowingPopover = false
    @State private var hideTask: Task<Void, Never>?

    private var progress: Double {
        let active = downloadManager.activeDownloads
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + $1.displayProgress } / Double(active.count)
    }

    var body: some View {
        let isDownloading = !downloadManager.activeDownloads.isEmpty
        Button {
            hideTask?.cancel()
            isShowingPopover.toggle()
        } label: {
            ZStack {
                if isDownloading {
                    Circle()
                        .stroke(theme.accent.opacity(0.2), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: progress)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(theme.accent)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(foregroundColor)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Downloads")
        .accessibilityLabel(Text("Downloads"))
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            DownloadsPopover {
                isShowingPopover = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    downloadManager.isShowingDownloadsHistory = true
                }
            }
            .environmentObject(downloadManager)
            .onHover { hovering in
                if hovering { hideTask?.cancel() }
            }
        }
        // A new download: shown for a few seconds, like Safari.
        .onChange(of: downloadManager.activeDownloads.count) { old, new in
            guard new > old else { return }
            isShowingPopover = true
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                isShowingPopover = false
            }
        }
    }
}

/// Today's browsing time beside the page.
struct TimeURLBarButton: View {
    let foregroundColor: Color
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            appState.showTimeSummary.toggle()
        } label: {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appState.showTimeSummary ? theme.accent : foregroundColor)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.showTimeSummary ? "Hide Browsing Time" : "Browsing Time")
        .accessibilityLabel(Text("Browsing Time"))
    }
}
