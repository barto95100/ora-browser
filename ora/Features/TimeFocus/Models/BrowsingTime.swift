import Foundation

/// Time spent on a site, an hour of a day: what the browsing time is kept as.
struct BrowsingTimeEntry: Equatable {
    let spaceID: UUID
    let domain: String
    /// The start of the hour.
    let hour: Date
    let seconds: Double
    /// Times the site was opened (came in front after another one).
    var opens = 0
}

/// A part of a stretch of time, within one hour.
struct HourSlice: Equatable {
    let hour: Date
    let seconds: Double
}

enum BrowsingTime {
    /// The site counted for a page: its registrable domain ("forum.hacf.fr"
    /// and "auth.hacf.fr" are "hacf.fr"), web pages only.
    static func domain(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return WebSite.registrableDomain(of: url)
    }

    /// A stretch of time cut at each hour.
    static func hourSlices(from start: Date, to end: Date, calendar: Calendar = .current) -> [HourSlice] {
        guard end > start else { return [] }
        var slices: [HourSlice] = []
        var cursor = start
        while cursor < end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
            let sliceEnd = min(hour.end, end)
            slices.append(HourSlice(hour: hour.start, seconds: sliceEnd.timeIntervalSince(cursor)))
            cursor = sliceEnd
        }
        return slices
    }

    /// "8 s", "12 min", "1 h 05".
    static func format(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}
