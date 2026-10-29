import SwiftUI

/// Covers a page whose site is blocked during focus, and pauses its media.
/// "Allow 5 min" opens it for a while; the page comes back at the break.
struct FocusBlockView: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var session = FocusSession.shared
    @Environment(\.theme) private var theme

    var body: some View {
        // Looked at again when an allowance ends (and when the phase changes).
        TimelineView(.explicit([.now] + session.allowedUntil.values.filter { $0 > .now }.sorted())) { context in
            if session.isBlocked(tab, now: context.date) {
                cover
                    .transition(.opacity)
                    .onAppear { tab.browserPage?.pauseAllMedia {} }
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.isBlocked(tab))
    }

    private var cover: some View {
        let site = BrowsingTime.domain(of: tab.url) ?? ""
        return ZStack {
            Rectangle().fill(theme.background)
            VStack(spacing: 14) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 34))
                    .foregroundColor(theme.accent)
                Text("Focus")
                    .font(.system(size: 22, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(site) is blocked · back in \(FocusCard.clock(session.remaining(at: context.date)))")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundColor(theme.mutedForeground)
                }
                HStack(spacing: 10) {
                    Button("Allow 5 min") { session.allow(site) }
                        .buttonStyle(FocusButtonStyle(color: theme.foreground, isProminent: false))
                    Button("End Focus") { session.stop() }
                        .buttonStyle(FocusButtonStyle(color: theme.accent, isProminent: true))
                }
                .padding(.top, 4)
            }
            .padding(40)
        }
    }
}

/// Address bar: the time left while a focus run goes on.
struct FocusIndicator: View {
    let foregroundColor: Color
    @EnvironmentObject var appState: AppState
    @ObservedObject private var session = FocusSession.shared
    @Environment(\.theme) private var theme

    var body: some View {
        if session.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button {
                    appState.showTimeSummary = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: session.isFocusing ? "moon.stars.fill" : "cup.and.saucer.fill")
                            .font(.system(size: 10))
                        Text(FocusCard.clock(session.remaining(at: context.date)))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .foregroundColor(session.isFocusing ? theme.accent : foregroundColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(session.phase?.title ?? "Focus")
            }
        }
    }
}
