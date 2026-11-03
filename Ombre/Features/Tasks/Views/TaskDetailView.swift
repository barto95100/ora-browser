import SwiftUI

/// A task's details, in a popover: title, due day, reminder, page, subtasks.
struct TaskDetailView: View {
    @Bindable var task: SpaceTask
    @ObservedObject var tab: Tab
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var newSubtask = ""

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { task.dueDate = $0 ? Calendar.current.startOfDay(for: Date()) : nil
                tabManager.saveTasks()
            }
        )
    }

    private var hasReminder: Binding<Bool> {
        Binding(
            get: { task.reminderDate != nil },
            set: { isOn in
                task.reminderDate = isOn ? Self.defaultReminder(due: task.dueDate) : nil
                reminderChanged()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .onSubmit { tabManager.saveTasks() }

            Divider()

            Toggle("Due date", isOn: hasDueDate)
            if task.dueDate != nil {
                DatePicker(
                    "Day",
                    selection: Binding(
                        get: { task.dueDate ?? Date() },
                        set: { task.dueDate = Calendar.current.startOfDay(for: $0)
                            tabManager.saveTasks()
                        }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            }

            Toggle("Remind me", isOn: hasReminder)
            if task.reminderDate != nil {
                DatePicker(
                    "When",
                    selection: Binding(
                        get: { task.reminderDate ?? Date() },
                        set: { task.reminderDate = $0
                            reminderChanged()
                        }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }

            Divider()

            pageSection

            if task.parent == nil {
                Divider()
                subtasksSection
            }

            Divider()

            Button(role: .destructive) {
                tabManager.deleteTask(task)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 280)
        // The popover grows with what is shown (due day, reminder): the
        // title was pushed out of it.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var pageSection: some View {
        if let page = task.pageURL {
            HStack(spacing: 6) {
                Image(systemName: "link")
                Button(task.pageTitle ?? page.absoluteString) { tab.openPeek(page) }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.accent)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    task.pageURLString = nil
                    task.pageTitle = nil
                    tabManager.saveTasks()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.mutedForeground)
                }
                .buttonStyle(.plain)
                .help("Remove the Page")
            }
        } else {
            Button {
                tabManager.attachPage(of: tab, to: task)
            } label: {
                Label("Attach Current Page", systemImage: "link.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.accent)
            .help(tab.title)
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtasks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.mutedForeground)
            ForEach(task.orderedSubtasks) { subtask in
                HStack(spacing: 6) {
                    Button {
                        tabManager.setDone(subtask, !subtask.isDone)
                    } label: {
                        Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(subtask.isDone ? theme.accent : theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    Text(subtask.title)
                        .strikethrough(subtask.isDone)
                        .foregroundColor(subtask.isDone ? theme.mutedForeground : theme.foreground)
                    Spacer(minLength: 0)
                    Button {
                        tabManager.deleteTask(subtask)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Subtask")
                }
            }
            TextField("Add subtask", text: $newSubtask)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    tabManager.addSubtask(newSubtask, to: task)
                    newSubtask = ""
                }
        }
    }

    private func reminderChanged() {
        TaskReminders.update(task)
        tabManager.saveTasks()
    }

    /// The reminder offered: 9:00 on the due day, or in an hour.
    static func defaultReminder(due: Date?, now: Date = Date()) -> Date {
        if let due, let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due),
           morning > now
        {
            return morning
        }
        let inAnHour = now.addingTimeInterval(3600)
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: inAnHour)
        components.minute = (components.minute ?? 0) / 5 * 5
        return Calendar.current.date(from: components) ?? inAnHour
    }
}
