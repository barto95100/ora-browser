import SwiftUI

/// Peek: a link previewed over the page, like Arc. Closes with the button, a
/// click beside it, Escape or ⌘W; "Open in New Tab" (⌘O) keeps the page as is.
struct PeekView: View {
    @ObservedObject var peek: PeekPage
    let onClose: () -> Void
    let onOpenInTab: () -> Void
    let onOpenInSplitView: () -> Void

    @Environment(\.theme) private var theme

    private let cornerRadius: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    toolbar
                    Divider().opacity(0.5)
                    if peek.isMovedToTab {
                        Color.clear
                    } else {
                        BrowserPageView(page: peek.page, onEscape: onClose)
                    }
                }
                .frame(width: proxy.size.width * 0.9, height: proxy.size.height * 0.92)
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.foreground.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 12)
            }
        }
        .onExitCommand(perform: onClose)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if peek.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: peek.url.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedForeground)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(peek.title.isEmpty ? peek.url.host ?? peek.url.absoluteString : peek.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                Text(peek.url.host ?? peek.url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            toolbarButton("rectangle.split.2x1", help: "Open in Split View", action: onOpenInSplitView)
            toolbarButton("arrow.up.left.and.arrow.down.right", help: "Open in New Tab (⌘O)", action: onOpenInTab)
            toolbarButton("xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.mutedForeground)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
