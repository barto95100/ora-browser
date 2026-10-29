import AppKit
import SwiftUI

/// The latest downloads, under the address bar's downloads button, like
/// Safari: progress while they go on; once done, a click opens the file, the
/// magnifier shows it in the Finder.
struct DownloadsPopover: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.theme) private var theme
    let onShowAll: () -> Void

    private static let shownCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Downloads")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            if downloadManager.recentDownloads.isEmpty {
                Text("No downloads yet")
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            ForEach(downloadManager.recentDownloads.prefix(Self.shownCount)) { download in
                DownloadsPopoverRow(download: download)
            }
            Divider().padding(.top, 6)
            Button(action: onShowAll) {
                Text("Show All Downloads")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
    }
}

private struct DownloadsPopoverRow: View {
    @ObservedObject var download: Download
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isDone: Bool {
        download.status == .completed
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(download.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if download.status == .downloading {
                    ProgressView(value: download.displayProgress)
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                }
                Text(statusText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(download.status == .failed ? .red : theme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovering && isDone ? theme.foreground.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if isDone { downloadManager.openFile(download) }
        }
        .help(isDone ? "Open \(download.fileName)" : download.fileName)
    }

    @ViewBuilder
    private var icon: some View {
        if isDone, let url = download.destinationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: download.status == .failed ? "exclamationmark.triangle" : "arrow.down.doc")
                .font(.system(size: 20))
                .foregroundColor(download.status == .failed ? .red : theme.accent)
                .frame(width: 30, height: 30)
        }
    }

    private var statusText: String {
        switch download.status {
        case .downloading, .pending:
            let total = download.displayFileSize > 0 ? " of \(Download.formattedSize(download.displayFileSize))" : ""
            return "\(Download.formattedSize(download.displayDownloadedBytes))\(total)"
        case .completed:
            return download.formattedFileSize
        case .failed:
            return download.error ?? "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch download.status {
        case .downloading, .pending:
            Button {
                downloadManager.cancelDownload(download)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(theme.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        case .completed:
            Button {
                downloadManager.openDownloadInFinder(download)
            } label: {
                Image(systemName: "magnifyingglass.circle.fill").foregroundColor(theme.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        case .failed, .cancelled:
            Button {
                downloadManager.retryDownload(download)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundColor(theme.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Try Again")
        }
    }
}
