import Foundation

/// History grouped by day for display: "Today", "Yesterday", then dates.
enum HistorySections {
    struct Section<Item> {
        let title: String
        let items: [Item]
    }

    /// Groups items already sorted from newest to oldest, keeping their order.
    static func byDay<Item>(
        _ items: [Item],
        date: (Item) -> Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Section<Item>] {
        var sections: [Section<Item>] = []
        var currentDay: Date?
        var currentItems: [Item] = []

        func closeSection() {
            guard let day = currentDay, !currentItems.isEmpty else { return }
            sections.append(Section(title: title(for: day, now: now, calendar: calendar), items: currentItems))
        }

        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if day != currentDay {
                closeSection()
                currentDay = day
                currentItems = []
            }
            currentItems.append(item)
        }
        closeSection()
        return sections
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        if calendar.component(.year, from: day) == calendar.component(.year, from: now) {
            return day.formatted(style)
        }
        return day.formatted(style.year())
    }
}

/// What "Clear History" removes, like Safari.
enum HistoryClearRange: CaseIterable, Identifiable {
    case lastHour
    case today
    case todayAndYesterday
    case all

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .lastHour: "the Last Hour"
        case .today: "Today"
        case .todayAndYesterday: "Today and Yesterday"
        case .all: "All History"
        }
    }

    /// Pages visited since this date are removed; nil removes everything.
    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastHour: now.addingTimeInterval(-3600)
        case .today: calendar.startOfDay(for: now)
        case .todayAndYesterday: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case .all: nil
        }
    }
}
