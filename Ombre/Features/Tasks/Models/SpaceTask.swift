import Foundation
import SwiftData

/// A task of a space's list (see `TasksPanel`), or a subtask of one: a due
/// day, a reminder (a macOS notification) and a page it is about, if any.
@Model
final class SpaceTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?
    /// The day it is due (its start), none by default.
    var dueDate: Date?
    /// When the reminder shows, none by default.
    var reminderDate: Date?
    var pageURLString: String?
    var pageTitle: String?
    /// Place in the list; subtasks are kept in their own order.
    var order: Int

    /// The space, for a task of the list (nil for a subtask).
    var container: TabContainer?
    /// The task, for a subtask.
    var parent: SpaceTask?
    @Relationship(deleteRule: .cascade, inverse: \SpaceTask.parent) var subtasks: [SpaceTask] = []

    init(title: String, order: Int) {
        id = UUID()
        self.title = title
        isDone = false
        createdAt = Date()
        self.order = order
    }

    var pageURL: URL? {
        pageURLString.flatMap(URL.init(string:))
    }

    /// The space of a task or of its parent.
    var space: TabContainer? {
        container ?? parent?.container
    }

    var orderedSubtasks: [SpaceTask] {
        subtasks.sorted { $0.order < $1.order }
    }
}

extension SpaceTask {
    /// Another window saved this task: tells the views reading it (see `Tab`).
    func noteChangedElsewhere() {
        note(\.title)
        note(\.isDone)
        note(\.completedAt)
        note(\.dueDate)
        note(\.reminderDate)
        note(\.pageURLString)
        note(\.pageTitle)
        note(\.order)
        note(\.parent)
        note(\.subtasks)
        note(\.container)
    }

    private func note(_ keyPath: KeyPath<SpaceTask, some Any>) {
        _$observationRegistrar.withMutation(of: self, keyPath: keyPath) {}
    }
}
