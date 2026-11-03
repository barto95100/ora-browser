import Foundation

/// When a task is due, seen from today: what its date chip says.
enum TaskDue: Equatable {
    case overdue
    case today
    case tomorrow
    case later
}

enum TaskSchedule {
    /// How a due day compares to `now`.
    static func due(_ dueDate: Date, now: Date = Date(), calendar: Calendar = .current) -> TaskDue {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dueDate)
        if day < today { return .overdue }
        if day == today { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), day == tomorrow { return .tomorrow }
        return .later
    }

    /// "Today", "Tomorrow", or the day ("3 Nov").
    static func label(for dueDate: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch due(dueDate, now: now, calendar: calendar) {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .overdue, .later:
            var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            if !calendar.isDate(dueDate, equalTo: now, toGranularity: .year) {
                style = style.year()
            }
            return dueDate.formatted(style)
        }
    }

    /// The order a new task takes: before all others (the list shows the
    /// newest first).
    static func orderForNewTask(existing orders: [Int]) -> Int {
        (orders.min() ?? 1) - 1
    }

    /// The order a new subtask takes: after the others.
    static func orderForNewSubtask(existing orders: [Int]) -> Int {
        (orders.max() ?? -1) + 1
    }

    /// Done subtasks out of all, for the row ("1/3"), nil without any.
    static func progress(done: Int, total: Int) -> String? {
        total > 0 ? "\(done)/\(total)" : nil
    }
}
