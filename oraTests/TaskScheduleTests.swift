import Foundation
@testable import Ora
import Testing

struct TaskScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    @Test func dueDaysAreSeenFromToday() {
        let now = date(29, 15)
        #expect(TaskSchedule.due(date(28, 23), now: now, calendar: calendar) == .overdue)
        #expect(TaskSchedule.due(date(29, 8), now: now, calendar: calendar) == .today)
        #expect(TaskSchedule.due(date(30, 0), now: now, calendar: calendar) == .tomorrow)
        #expect(TaskSchedule.due(date(31), now: now, calendar: calendar) == .later)
    }

    @Test func labelsNameTodayAndTomorrow() {
        let now = date(29)
        #expect(TaskSchedule.label(for: date(29), now: now, calendar: calendar) == "Today")
        #expect(TaskSchedule.label(for: date(30), now: now, calendar: calendar) == "Tomorrow")
        #expect(TaskSchedule.label(for: date(3, month: 11), now: now, calendar: calendar).contains("3"))
        #expect(TaskSchedule.label(for: date(3, month: 1, year: 2027), now: now, calendar: calendar).contains("2027"))
    }

    @Test func newTasksComeFirstAndSubtasksLast() {
        #expect(TaskSchedule.orderForNewTask(existing: []) == 0)
        #expect(TaskSchedule.orderForNewTask(existing: [0, 3, -2]) == -3)
        #expect(TaskSchedule.orderForNewSubtask(existing: []) == 0)
        #expect(TaskSchedule.orderForNewSubtask(existing: [0, 1]) == 2)
    }

    @Test func progressCountsDoneSubtasks() {
        #expect(TaskSchedule.progress(done: 1, total: 3) == "1/3")
        #expect(TaskSchedule.progress(done: 0, total: 0) == nil)
    }

    @MainActor @Test func theReminderOfferedIsInTheFuture() {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let onTheDay = TaskDetailView.defaultReminder(due: Calendar.current.startOfDay(for: tomorrow), now: now)
        #expect(Calendar.current.component(.hour, from: onTheDay) == 9)
        #expect(TaskDetailView.defaultReminder(due: nil, now: now) > now)
    }
}
