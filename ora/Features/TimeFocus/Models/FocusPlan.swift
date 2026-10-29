import Foundation

/// A part of a focus run: focus, then a break when cycles repeat.
enum FocusPhase: String, Codable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
        }
    }
}

/// The durations of a focus run, from the settings.
struct FocusPlan: Equatable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    /// Focus phases before a long break.
    var cyclesBeforeLongBreak = 4
    /// Whether focus and breaks follow each other until stopped.
    var repeats = false

    func duration(of phase: FocusPhase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: focusMinutes
        case .shortBreak: breakMinutes
        case .longBreak: longBreakMinutes
        }
        return TimeInterval(max(minutes, 1) * 60)
    }

    /// What follows a phase; `completedCycles` counts the focus phases done,
    /// the one just ended included. Nil: the run ends.
    func phase(after phase: FocusPhase, completedCycles: Int) -> FocusPhase? {
        switch phase {
        case .focus:
            guard repeats else { return nil }
            let cycles = max(cyclesBeforeLongBreak, 1)
            return completedCycles % cycles == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }
}

/// Which sites are kept closed during focus.
enum FocusBlocking {
    /// The site of what the user typed ("https://www.YouTube.com/watch",
    /// "youtube.com", "m.youtube.com" are "youtube.com"); nil if not a site.
    static func site(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let site = BrowsingTime.domain(of: url), site.contains(".")
        else { return nil }
        return site
    }

    /// Whether a page's site is closed: in the list, and not allowed for a
    /// while ("Allow 5 min").
    static func isBlocked(site: String?, blocked: [String], allowedUntil: [String: Date], now: Date) -> Bool {
        guard let site, blocked.contains(site) else { return false }
        if let until = allowedUntil[site], until > now { return false }
        return true
    }
}
