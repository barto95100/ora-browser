import Foundation
@testable import Ora
import Testing

struct FocusPlanTests {
    @Test func aSingleFocusEnds() {
        let plan = FocusPlan(focusMinutes: 25, repeats: false)
        #expect(plan.phase(after: .focus, completedCycles: 1) == nil)
        #expect(plan.duration(of: .focus) == 25 * 60)
    }

    @Test func cyclesAlternateWithALongBreak() {
        let plan = FocusPlan(breakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 3, repeats: true)
        #expect(plan.phase(after: .focus, completedCycles: 1) == .shortBreak)
        #expect(plan.phase(after: .focus, completedCycles: 2) == .shortBreak)
        #expect(plan.phase(after: .focus, completedCycles: 3) == .longBreak)
        #expect(plan.phase(after: .shortBreak, completedCycles: 1) == .focus)
        #expect(plan.phase(after: .longBreak, completedCycles: 3) == .focus)
        #expect(plan.duration(of: .longBreak) == 15 * 60)
    }

    @Test func typedSitesBecomeTheirDomain() {
        #expect(FocusBlocking.site(from: "https://www.YouTube.com/watch?v=1") == "youtube.com")
        #expect(FocusBlocking.site(from: " m.youtube.com ") == "youtube.com")
        #expect(FocusBlocking.site(from: "forum.hacf.fr") == "hacf.fr")
        #expect(FocusBlocking.site(from: "not a site") == nil)
        #expect(FocusBlocking.site(from: "localhost") == nil)
    }

    @Test func anAllowedSiteOpensForAWhile() {
        let now = Date()
        let blocked = ["youtube.com"]
        #expect(FocusBlocking.isBlocked(site: "youtube.com", blocked: blocked, allowedUntil: [:], now: now))
        #expect(!FocusBlocking.isBlocked(site: "github.com", blocked: blocked, allowedUntil: [:], now: now))
        #expect(!FocusBlocking.isBlocked(site: nil, blocked: blocked, allowedUntil: [:], now: now))
        let allowed = ["youtube.com": now.addingTimeInterval(60)]
        #expect(!FocusBlocking.isBlocked(site: "youtube.com", blocked: blocked, allowedUntil: allowed, now: now))
        #expect(FocusBlocking.isBlocked(
            site: "youtube.com", blocked: blocked, allowedUntil: allowed, now: now.addingTimeInterval(61)
        ))
    }

    @MainActor @Test func daysAreKeyedByDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)) ?? Date()
        #expect(FocusSettings.dayKey(for: date, calendar: calendar) == "2026-03-07")
    }

    @MainActor @Test func clocksReadLikeATimer() {
        #expect(FocusCard.clock(25 * 60) == "25:00")
        #expect(FocusCard.clock(59.2) == "1:00")
        #expect(FocusCard.clock(3600 + 65) == "1:01:05")
    }
}
