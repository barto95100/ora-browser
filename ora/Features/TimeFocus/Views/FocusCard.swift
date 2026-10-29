import SwiftUI

/// The focus card: a ring with the time left, start / stop, and the day's
/// goal. In the time summary beside the page and in the large panel.
struct FocusCard: View {
    let spaceID: UUID?
    @ObservedObject private var session = FocusSession.shared
    @ObservedObject private var settings = FocusSettings.shared
    @Environment(\.theme) private var theme

    private var blockedCount: Int {
        spaceID.map { settings.blockedSites(in: $0).count } ?? 0
    }

    var body: some View {
        // Redrawn every second while a phase runs; not at all otherwise.
        TimelineView(.periodic(from: .now, by: session.isRunning ? 1 : 3600)) { context in
            HStack(alignment: .center, spacing: 16) {
                ring(now: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.phase?.title ?? "Focus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle(now: context.date))
                        .font(.system(size: 11))
                        .foregroundColor(theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    buttons
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.foreground.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.foreground.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Ring

    private func ring(now: Date) -> some View {
        ZStack {
            Circle()
                .stroke(theme.foreground.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: session.isRunning ? 1 - session.progress(at: now) : goalProgress)
                .stroke(
                    session.phase == .focus || !session.isRunning ? theme.accent : Color.green,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: session.progress(at: now))
            if session.isRunning {
                Text(Self.clock(session.remaining(at: now)))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
            } else {
                VStack(spacing: 0) {
                    Text("\(settings.focusMinutes)")
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    Menu {
                        ForEach(FocusSettings.durationChoices, id: \.self) { minutes in
                            Button("\(minutes) min") { settings.focusMinutes = minutes }
                        }
                    } label: {
                        Text("min ⌄").font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Focus Duration")
                }
            }
        }
        .frame(width: 84, height: 84)
    }

    /// Without a run, the ring shows the day's goal.
    private var goalProgress: Double {
        guard settings.dailyGoalMinutes > 0 else { return 0 }
        return min(settings.focusSeconds() / Double(settings.dailyGoalMinutes * 60), 1)
    }

    // MARK: - Text and buttons

    private func subtitle(now: Date) -> String {
        var lines: [String] = []
        if let end = session.phaseEnd, session.isRunning {
            let cycle = session.completedCycles + (session.isFocusing ? 1 : 0)
            let ends = "Ends at \(end.formatted(date: .omitted, time: .shortened))"
            lines.append(settings.repeats ? "\(ends) · cycle \(cycle)" : ends)
        }
        if session.phase != .shortBreak, session.phase != .longBreak {
            lines.append(
                blockedCount == 0 ? "Nothing is blocked during focus in this space."
                    : "\(blockedCount) site\(blockedCount == 1 ? "" : "s") blocked during focus."
            )
        } else {
            lines.append("Blocked sites are open during the break.")
        }
        if settings.dailyGoalMinutes > 0 {
            let done = Int(settings.focusSeconds() / 60)
            lines.append("Today: \(done) / \(settings.dailyGoalMinutes) min")
        }
        return lines.joined(separator: "\n")
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if !session.isRunning {
                Button("Start Focus") { session.start() }
                    .buttonStyle(FocusButtonStyle(color: theme.accent, isProminent: true))
            } else {
                if !session.isFocusing {
                    Button("Skip Break") { session.skipBreak() }
                        .buttonStyle(FocusButtonStyle(color: theme.accent, isProminent: true))
                }
                Button("Stop") { session.stop() }
                    .buttonStyle(FocusButtonStyle(color: theme.foreground, isProminent: false))
            }
        }
    }

    /// "24:59", "1:05:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }
}

/// A small filled or outlined button of the focus card.
struct FocusButtonStyle: ButtonStyle {
    let color: Color
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundColor(isProminent ? .white : color)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isProminent ? color : color.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
