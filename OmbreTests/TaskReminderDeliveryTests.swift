import Foundation
@testable import Ombre
import Testing

/// When a task's reminder goes off: on its minute, or at once when the
/// minute chosen has already come (set at 16:26 at 16:26:30, it used to wait
/// for macOS to notice the past minute, two minutes later).
struct TaskReminderDeliveryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")! // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour, minute: minute, second: second))
            ?? .distantPast
    }

    private func delivery(_ reminder: Date?, now: Date, isDone: Bool = false, isBeingSet: Bool = true)
        -> TaskReminders.Delivery
    {
        TaskReminders.delivery(
            reminder: reminder, isDone: isDone, isBeingSet: isBeingSet, now: now, calendar: calendar
        )
    }

    @Test func aReminderSetForTheCurrentMinuteGoesOffAtOnce() {
        #expect(delivery(date(16, 26, 40), now: date(16, 26, 30)) == .soon)
        #expect(delivery(date(16, 26), now: date(16, 26, 30)) == .soon)
    }

    @Test func aReminderSetForAMinuteGoneGoesOffAtOnce() {
        #expect(delivery(date(16, 20), now: date(16, 26, 30)) == .soon)
    }

    @Test func aReminderSetAheadGoesOffOnItsMinute() {
        let expected = DateComponents(year: 2026, month: 11, day: 20, hour: 16, minute: 27)
        #expect(delivery(date(16, 27, 15), now: date(16, 26, 30)) == .onMinute(expected))
        #expect(delivery(date(16, 27), now: date(16, 26, 59)) == .onMinute(expected))
    }

    @Test func aTimeLongGoneRemindsOnlyWhenBeingSet() {
        // A task marked undone, its title changed…: no reminder of the past.
        #expect(delivery(date(9, 0), now: date(16, 26), isBeingSet: false) == .none)
        let ahead = delivery(date(17, 0), now: date(16, 26), isBeingSet: false)
        #expect(ahead == .onMinute(DateComponents(year: 2026, month: 11, day: 20, hour: 17, minute: 0)))
    }

    @Test func noReminderForADoneTaskOrNone() {
        #expect(delivery(date(17, 0), now: date(16, 26), isDone: true) == .none)
        #expect(delivery(nil, now: date(16, 26)) == .none)
    }

    @Test func theMessageShowsWhenTheMinuteHasCome() {
        let now = Date()
        #expect(TaskReminders.isDueNow(now, isDone: false, now: now))
        #expect(!TaskReminders.isDueNow(now.addingTimeInterval(120), isDone: false, now: now))
        #expect(!TaskReminders.isDueNow(nil, isDone: false, now: now))
        #expect(!TaskReminders.isDueNow(now, isDone: true, now: now))
    }
}
