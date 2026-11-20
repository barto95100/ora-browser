import Foundation
import UserNotifications

/// The reminders of tasks: macOS notifications at their time. A click on
/// one opens the task's space and its list (see `WebNotificationCenter`).
@MainActor
enum TaskReminders {
    nonisolated static let taskIDKey = "spaceTaskID"
    nonisolated static let spaceIDKey = "spaceTaskSpaceID"

    private static var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    nonisolated static func identifier(for taskID: UUID) -> String {
        "task/\(taskID.uuidString)"
    }

    /// When a reminder goes off.
    enum Delivery: Equatable {
        /// Never (none, done, or its time passed long before it was set).
        case none
        /// In a few seconds: its minute has come as it is set.
        case soon
        /// At this minute.
        case onMinute(DateComponents)
    }

    /// Seconds before a reminder set for a minute already come goes off:
    /// time to change it again (each change replaces the one waiting).
    nonisolated static let dueNowDelay: TimeInterval = 5

    /// When the reminder goes off. A minute already come (or gone) sends it
    /// at once when the reminder is being set, and never otherwise (a task
    /// marked undone does not remind of a time long past).
    nonisolated static func delivery(
        reminder: Date?,
        isDone: Bool,
        isBeingSet: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Delivery {
        guard let reminder, !isDone else { return .none }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
        // Notifications go off on the minute: past its start, it has come.
        guard let minute = calendar.date(from: components), minute <= now else { return .onMinute(components) }
        return isBeingSet ? .soon : .none
    }

    /// Whether the reminder just set goes off at once (its minute has come).
    nonisolated static func isDueNow(_ reminder: Date?, isDone: Bool, now: Date = Date()) -> Bool {
        delivery(reminder: reminder, isDone: isDone, isBeingSet: true, now: now) == .soon
    }

    /// Schedules the task's reminder again (or removes it: none, past, done).
    /// `isBeingSet`: its time was just chosen, sent at once if already come.
    static func update(_ task: SpaceTask, isBeingSet: Bool = false) {
        let identifier = identifier(for: task.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let trigger: UNNotificationTrigger
        switch delivery(reminder: task.reminderDate, isDone: task.isDone, isBeingSet: isBeingSet) {
        case .none:
            return
        case .soon:
            // Set again: the banner of an earlier try goes.
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: dueNowDelay, repeats: false)
        case let .onMinute(components):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        WebNotificationCenter.shared.requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? String(localized: "Task") : task.title
        if let parent = task.parent {
            content.subtitle = parent.title
        } else if let space = task.space {
            content.subtitle = space.name
        }
        if let pageTitle = task.pageTitle {
            content.body = pageTitle
        }
        content.sound = .default
        content.threadIdentifier = "ombre-tasks"
        var userInfo = [taskIDKey: task.id.uuidString]
        if let space = task.space {
            userInfo[spaceIDKey] = space.id.uuidString
        }
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// The task and its subtasks remind no more (deleted).
    static func cancel(_ task: SpaceTask) {
        let identifiers = ([task] + task.subtasks).map { identifier(for: $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
