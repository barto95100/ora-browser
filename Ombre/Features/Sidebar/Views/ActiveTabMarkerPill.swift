import SwiftUI

extension EnvironmentValues {
    /// The rows the tab list's pill follows (see `ActiveTabMarker`).
    @Entry var activeTabMarkerTarget: ActiveTabMarker.Target?
    /// Where those rows report their frames.
    @Entry var activeTabMarkerState: ActiveTabMarkerState?
}

extension View {
    /// A row of the tab list that may stand for the active tab or lead to it:
    /// `ids` are its tabs (a split row: both), or its folder or group.
    func activeTabMarkerRow(_ ids: [UUID]) -> some View {
        modifier(ActiveTabMarkerRow(ids: ids))
    }
}

/// Reports the row's frame while the pill follows it, and only then.
private struct ActiveTabMarkerRow: ViewModifier {
    let ids: [UUID]
    @Environment(\.activeTabMarkerTarget) private var target
    @Environment(\.activeTabMarkerState) private var state

    private var followedID: UUID? {
        guard let target else { return nil }
        return ids.first { $0 == target.tabID || $0 == target.destinationID }
    }

    func body(content: Content) -> some View {
        // In the background: the row itself keeps its identity (and state).
        content.background {
            if let id = followedID, let state {
                RowFrameReporter(id: id, state: state)
            }
        }
    }
}

private struct RowFrameReporter: View {
    let id: UUID
    let state: ActiveTabMarkerState
    @State private var reporter = UUID()

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ActiveTabMarker.coordinateSpace))
            } action: { frame in
                state.report(frame, for: id, by: reporter)
            }
            .onDisappear { state.remove(id, by: reporter) }
    }
}

/// The pill at one edge of the tab list: the active tab's icon and an arrow
/// towards it; its title in the tooltip.
struct ActiveTabMarkerPill: View {
    let state: ActiveTabMarkerState
    let edge: ActiveTabMarker.Edge
    let tab: Tab?
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if state.edge == edge, let tab {
                Button(action: action) {
                    HStack(spacing: 4) {
                        FavIcon(
                            isWebViewReady: tab.isWebViewReady,
                            favicon: tab.favicon,
                            faviconLocalFile: tab.faviconLocalFile,
                            textColor: theme.foreground
                        )
                        Image(systemName: edge == .top ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(theme.foreground.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(theme.border, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.displayName)
                .accessibilityLabel(Text(ActiveTabMarker.accessibilityLabel(edge)))
                .transition(.opacity)
            }
        }
        .padding(edge == .top ? .top : .bottom, 6)
        .animation(.easeOut(duration: 0.15), value: state.edge)
    }
}
