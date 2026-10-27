import Foundation
@testable import Ora
import Testing

struct HistorySectionsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func entriesAreGroupedByDayInOrder() {
        let now = date(27, 12)
        let visits = [date(27, 10), date(27, 9), date(26, 21), date(20, 8)]

        let sections = HistorySections.byDay(visits, date: { $0 }, now: now, calendar: calendar)

        #expect(sections.map(\.title).prefix(2) == ["Today", "Yesterday"])
        #expect(sections.map(\.items.count) == [2, 1, 1])
        #expect(sections[0].items == [date(27, 10), date(27, 9)])
    }

    @Test func olderDaysAreTitledWithTheirDate() {
        let now = date(27, 12)
        let title = HistorySections.title(for: date(20, 0), now: now, calendar: calendar)
        #expect(title != "Today" && title != "Yesterday" && title.contains("20"))
    }

    @Test func noEntriesMeansNoSections() {
        #expect(HistorySections.byDay([Date](), date: { $0 }, calendar: calendar).isEmpty)
    }

    @Test func clearRangesStartWhereSafariDoes() {
        let now = date(27, 12)
        #expect(HistoryClearRange.lastHour.startDate(now: now, calendar: calendar) == date(27, 11))
        #expect(HistoryClearRange.today.startDate(now: now, calendar: calendar) == date(27, 0))
        #expect(HistoryClearRange.todayAndYesterday.startDate(now: now, calendar: calendar) == date(26, 0))
        #expect(HistoryClearRange.all.startDate(now: now, calendar: calendar) == nil)
    }
}
