import Foundation
import SwiftData

/// The tasks of spaces, kept with the tabs (SwiftData).
extension TabManager {
    @discardableResult
    func addTask(_ title: String, to space: TabContainer) -> SpaceTask? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let task = SpaceTask(title: title, order: TaskSchedule.orderForNewTask(existing: space.tasks.map(\.order)))
        space.tasks.append(task)
        saveTasks()
        return task
    }

    @discardableResult
    func addSubtask(_ title: String, to parent: SpaceTask) -> SpaceTask? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let order = TaskSchedule.orderForNewSubtask(existing: parent.subtasks.map(\.order))
        let subtask = SpaceTask(title: title, order: order)
        parent.subtasks.append(subtask)
        saveTasks()
        return subtask
    }

    func setDone(_ task: SpaceTask, _ isDone: Bool) {
        task.isDone = isDone
        task.completedAt = isDone ? Date() : nil
        TaskReminders.update(task)
        saveTasks()
    }

    func deleteTask(_ task: SpaceTask) {
        TaskReminders.cancel(task)
        if let parent = task.parent {
            parent.subtasks.removeAll { $0.id == task.id }
        } else {
            task.container?.tasks.removeAll { $0.id == task.id }
        }
        modelContext.delete(task)
        saveTasks()
    }

    /// The page shown in the tab, attached to the task.
    func attachPage(of tab: Tab, to task: SpaceTask) {
        task.pageURLString = tab.url.absoluteString
        task.pageTitle = tab.title
        saveTasks()
    }

    func saveTasks() {
        try? modelContext.save()
    }
}

extension TabManager {
    /// The space of a reminder clicked, shown (its last tab).
    func showTasks(ofSpace spaceID: UUID?) {
        guard let spaceID, activeContainer?.id != spaceID,
              let space = (try? modelContext.fetch(FetchDescriptor<TabContainer>()))?.first(where: { $0.id == spaceID })
        else { return }
        activateContainer(space)
    }
}
