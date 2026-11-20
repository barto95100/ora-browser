import Foundation

/// How long a tab not shown stays before it is closed (Settings › General,
/// and each space's own limit), like Arc: a few set delays, never, or a
/// number of hours, days or weeks.
enum TabClosingDelay {
    enum Unit: String, CaseIterable, Identifiable {
        case hours
        case days
        case weeks

        var id: String {
            rawValue
        }

        var seconds: TimeInterval {
            switch self {
            case .hours: return 3600
            case .days: return 86400
            case .weeks: return 604_800
            }
        }
    }

    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400
    /// Saved for "Never" (the setting has always kept a number).
    static let never: TimeInterval = 365 * day
    /// The general delay when none was ever chosen.
    static let defaultDelay: TimeInterval = day

    /// The delays offered, shortest first: 12 hours, 1 day, 2 days, 1 week, 1 month.
    static let presets: [TimeInterval] = [12 * hour, day, 2 * day, 7 * day, 30 * day]

    /// The longest custom delay that makes sense, and the shortest.
    static let longest = 52 * Unit.weeks.seconds
    static let shortest = hour

    static func isNever(_ seconds: TimeInterval) -> Bool {
        seconds >= never
    }

    /// A saved delay as used: none saved (0) is the default, too short is an
    /// hour, too long is never.
    static func normalized(_ saved: TimeInterval) -> TimeInterval {
        guard saved > 0 else { return defaultDelay }
        if saved >= never { return never }
        return max(saved, shortest)
    }

    /// A custom delay typed: `count` hours, days or weeks, from an hour to a
    /// year; nil if `count` is not a positive number.
    static func custom(_ count: Int, _ unit: Unit) -> TimeInterval? {
        guard count > 0 else { return nil }
        return min(TimeInterval(count) * unit.seconds, longest)
    }

    /// A delay as a number of its largest whole unit (36 hours: 36 hours;
    /// 14 days: 2 weeks), to show it or edit it again.
    static func parts(of seconds: TimeInterval) -> (count: Int, unit: Unit) {
        for unit in Unit.allCases.reversed() where seconds >= unit.seconds
            && seconds.truncatingRemainder(dividingBy: unit.seconds) == 0
        {
            return (Int(seconds / unit.seconds), unit)
        }
        return (max(1, Int((seconds / Unit.hours.seconds).rounded())), .hours)
    }

    /// The delay in words: "12 hours", "1 day", "1 month", "Never".
    static func title(_ seconds: TimeInterval) -> String {
        if isNever(seconds) { return String(localized: "Never") }
        if seconds == 30 * day { return String(localized: "1 month") }
        let (count, unit) = parts(of: seconds)
        switch unit {
        case .hours: return String(localized: "\(count) hours")
        case .days: return String(localized: "\(count) days")
        case .weeks: return String(localized: "\(count) weeks")
        }
    }

    // MARK: - A space's own limit

    /// What a space kept before delays could be any length.
    static func spaceDelay(fromLegacy raw: String) -> TimeInterval? {
        switch raw {
        case "1 Hour": return hour // no translation
        case "1 Day": return day // no translation
        case "1 Week": return 7 * day // no translation
        default: return nil
        }
    }
}
