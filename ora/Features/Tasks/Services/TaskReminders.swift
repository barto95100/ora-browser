import Foundation
import UserNotifications

/// The reminders of tasks: macOS notifications at their time. A click on
/// one opens the task's space and its list (see `WebNotificationCenter`).
enum TaskReminders {
    static let taskIDKey = "spaceTaskID"
    static let spaceIDKey = "spaceTaskSpaceID"

    private static var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    static func identifier(for taskID: UUID) -> String {
        "task/\(taskID.uuidString)"
    }

    /// Schedules the task's reminder again (or removes it: none, past, done).
    static func update(_ task: SpaceTask) {
        let identifier = identifier(for: task.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let date = task.reminderDate, date > Date(), !task.isDone else { return }
        WebNotificationCenter.shared.requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "Task" : task.title
        if let parent = task.parent {
            content.subtitle = parent.title
        } else if let space = task.space {
            content.subtitle = space.name
        }
        if let pageTitle = task.pageTitle {
            content.body = pageTitle
        }
        content.sound = .default
        content.threadIdentifier = "ora-tasks"
        var userInfo = [taskIDKey: task.id.uuidString]
        if let space = task.space {
            userInfo[spaceIDKey] = space.id.uuidString
        }
        content.userInfo = userInfo
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// The task and its subtasks remind no more (deleted).
    static func cancel(_ task: SpaceTask) {
        let identifiers = ([task] + task.subtasks).map { identifier(for: $0.id) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
