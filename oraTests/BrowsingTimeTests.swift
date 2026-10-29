import Foundation
@testable import Ora
import Testing

struct BrowsingTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    @Test func webPagesCountByRegistrableDomain() throws {
        #expect(try BrowsingTime.domain(of: #require(URL(string: "https://www.GitHub.com/a"))) == "github.com")
        #expect(try BrowsingTime.domain(of: #require(URL(string: "http://forum.hacf.fr"))) == "hacf.fr")
        #expect(try BrowsingTime.domain(of: #require(URL(string: "https://news.bbc.co.uk/x"))) == "bbc.co.uk")
        #expect(try BrowsingTime.domain(of: #require(URL(string: "file:///tmp/a.html"))) == nil)
        #expect(try BrowsingTime.domain(of: #require(URL(string: "about:blank"))) == nil)
    }

    @Test func aStretchIsCutAtEachHour() {
        let slices = BrowsingTime.hourSlices(from: date(29, 9, 50), to: date(29, 11, 5), calendar: calendar)
        #expect(slices == [
            HourSlice(hour: date(29, 9), seconds: 600),
            HourSlice(hour: date(29, 10), seconds: 3600),
            HourSlice(hour: date(29, 11), seconds: 300)
        ])
        #expect(BrowsingTime.hourSlices(from: date(29, 9), to: date(29, 9), calendar: calendar).isEmpty)
    }

    @Test func durationsReadEasily() {
        #expect(BrowsingTime.format(0) == "0 s")
        #expect(BrowsingTime.format(20.6) == "20 s")
        #expect(BrowsingTime.format(12 * 60 + 30) == "12 min")
        #expect(BrowsingTime.format(3600 + 5 * 60) == "1 h 05")
    }

    @Test func aDayReportHasHoursAndSites() {
        let work = UUID()
        let home = UUID()
        let entries = [
            BrowsingTimeEntry(spaceID: work, domain: "github.com", hour: date(29, 9), seconds: 1200),
            BrowsingTimeEntry(spaceID: work, domain: "forum.hacf.fr", hour: date(29, 9), seconds: 600),
            BrowsingTimeEntry(spaceID: work, domain: "github.com", hour: date(29, 14), seconds: 300),
            BrowsingTimeEntry(spaceID: home, domain: "youtube.com", hour: date(29, 21), seconds: 3000),
            BrowsingTimeEntry(spaceID: work, domain: "github.com", hour: date(28, 9), seconds: 999)
        ]
        let report = BrowsingTimeReport(
            entries: entries, period: .day, containing: date(29, 12), spaceID: work, calendar: calendar
        )
        #expect(report.total == 2100)
        #expect(report.sites == [
            SiteTime(domain: "github.com", seconds: 1500),
            SiteTime(domain: "forum.hacf.fr", seconds: 600)
        ])
        #expect(report.buckets.count == 24)
        #expect(report.buckets[9].seconds == 1800)
        #expect(report.buckets[9].sites.first?.domain == "github.com")
        #expect(report.buckets[21].seconds == 0)

        let all = BrowsingTimeReport(entries: entries, period: .day, containing: date(29, 12), calendar: calendar)
        #expect(all.total == 5100)
        #expect(all.sites.first?.domain == "youtube.com")
    }

    @Test func aSiteCanBeShownAlone() {
        let space = UUID()
        let entries = [
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(29, 9), seconds: 1200),
            BrowsingTimeEntry(spaceID: space, domain: "forum.hacf.fr", hour: date(29, 10), seconds: 600)
        ]
        let report = BrowsingTimeReport(
            entries: entries, period: .day, containing: date(29, 12), domain: "forum.hacf.fr", calendar: calendar
        )
        #expect(report.total == 600)
        #expect(report.buckets[9].seconds == 0)
        #expect(report.sites.count == 2)
    }

    @Test func opensAreAddedUpBySite() {
        let space = UUID()
        let entries = [
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(29, 9), seconds: 60, opens: 2),
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(29, 10), seconds: 60, opens: 3)
        ]
        let report = BrowsingTimeReport(entries: entries, period: .day, containing: date(29, 12), calendar: calendar)
        #expect(report.sites.first?.opens == 5)
    }

    @Test func aWeekReportHasDays() {
        let space = UUID()
        let entries = [
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(26, 9), seconds: 600),
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(26, 15), seconds: 600),
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(29, 9), seconds: 300),
            BrowsingTimeEntry(spaceID: space, domain: "github.com", hour: date(25, 9), seconds: 999)
        ]
        let report = BrowsingTimeReport(entries: entries, period: .week, containing: date(29, 12), calendar: calendar)
        #expect(report.buckets.count == 7)
        #expect(report.buckets[0].start == date(26, 0))
        #expect(report.buckets[0].seconds == 1200)
        #expect(report.buckets[3].seconds == 300)
        #expect(report.total == 1500)
    }
}
