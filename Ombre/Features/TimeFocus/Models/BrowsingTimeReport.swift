import Foundation

/// The span the dashboard shows: a day (by hour) or a week (by day).
enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"

    var id: String {
        rawValue
    }

    /// The bars of the chart: hours of a day, days of a week.
    var bucketComponent: Calendar.Component {
        self == .day ? .hour : .day
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = self == .day ? .day : .weekOfYear
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    /// The same span, `count` before (negative) or after.
    func moving(_ date: Date, by count: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: self == .day ? .day : .weekOfYear, value: count, to: date) ?? date
    }
}

struct SiteTime: Identifiable, Equatable {
    let domain: String
    let seconds: Double
    var opens = 0

    var id: String {
        domain
    }
}

/// A bar of the chart: its time and its main sites.
struct TimeBucket: Identifiable, Equatable {
    let start: Date
    let seconds: Double
    let sites: [SiteTime]

    var id: Date {
        start
    }
}

/// Browsing time of a day or week, of one space or all, of one site or all.
struct BrowsingTimeReport: Equatable {
    let interval: DateInterval
    let total: Double
    let sites: [SiteTime]
    let buckets: [TimeBucket]

    init(
        entries: [BrowsingTimeEntry],
        period: ReportPeriod,
        containing date: Date,
        spaceID: UUID? = nil,
        domain: String? = nil,
        calendar: Calendar = .current
    ) {
        let interval = period.interval(containing: date, calendar: calendar)
        self.interval = interval
        let kept = entries.filter { entry in
            interval.contains(entry.hour) && entry.hour < interval.end
                && (spaceID == nil || entry.spaceID == spaceID)
        }
        sites = Self.sites(of: kept)
        let shown = domain.map { domain in kept.filter { $0.domain == domain } } ?? kept
        total = shown.reduce(0) { $0 + $1.seconds }

        var starts: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: period.bucketComponent, value: 1, to: cursor) else { break }
            cursor = next
        }
        let byBucket = Dictionary(grouping: shown) { entry in
            calendar.dateInterval(of: period.bucketComponent, for: entry.hour)?.start ?? entry.hour
        }
        buckets = starts.map { start in
            let entries = byBucket[start] ?? []
            return TimeBucket(
                start: start,
                seconds: entries.reduce(0) { $0 + $1.seconds },
                sites: Array(Self.sites(of: entries).prefix(3))
            )
        }
    }

    /// Sites by time spent, most first.
    private static func sites(of entries: [BrowsingTimeEntry]) -> [SiteTime] {
        Dictionary(grouping: entries, by: \.domain)
            .map { domain, entries in
                SiteTime(
                    domain: domain,
                    seconds: entries.reduce(0) { $0 + $1.seconds },
                    opens: entries.reduce(0) { $0 + $1.opens }
                )
            }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.domain < $1.domain }
    }
}
