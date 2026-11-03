import SwiftUI

/// A task of the list: its box, its title (edited in place), its due day,
/// reminder and page; its subtasks below when unfolded.
struct TaskRow: View {
    @Bindable var task: SpaceTask
    @ObservedObject var tab: Tab
    var isSubtask = false
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme

    @State private var isHovering = false
    @State private var isShowingDetails = false
    @State private var isExpanded = false
    @State private var newSubtask = ""
    @State private var isEditingTitle = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tabManager.setDone(task, !task.isDone) }
                } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: isSubtask ? 12 : 14))
                        .foregroundColor(task.isDone ? theme.accent : theme.mutedForeground)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    title
                    if !isSubtask { badges }
                }

                Spacer(minLength: 0)

                if isHovering || isShowingDetails {
                    Button {
                        isShowingDetails = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .help("Details")
                    .popover(isPresented: $isShowingDetails, arrowEdge: .leading) {
                        TaskDetailView(task: task, tab: tab)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                isHovering ? theme.mutedBackground.opacity(0.6) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .onHover { isHovering = $0 }
            .contextMenu { menu }

            if isExpanded, !isSubtask {
                subtaskList
            }
        }
    }

    // MARK: - Title

    /// Text, edited after a click: a field would take the right click (its
    /// text menu) from the task's menu.
    @ViewBuilder
    private var title: some View {
        let font = Font.system(size: isSubtask ? 12 : 13)
        if isEditingTitle {
            TextField("Task", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isTitleFocused)
                .onSubmit { isTitleFocused = false }
                .onChange(of: isTitleFocused) { _, isFocused in
                    if !isFocused { endTitleEditing() }
                }
                .onExitCommand { isTitleFocused = false }
                .onAppear { isTitleFocused = true }
        } else {
            Text(task.title.isEmpty ? "Task" : task.title)
                .font(font)
                .strikethrough(task.isDone)
                .foregroundColor(
                    task.isDone || task.title.isEmpty ? theme.mutedForeground : theme.foreground
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isEditingTitle = true }
        }
    }

    private func endTitleEditing() {
        isEditingTitle = false
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        tabManager.saveTasks()
    }

    // MARK: - Badges

    @ViewBuilder
    private var badges: some View {
        let subtasks = task.subtasks
        let progress = TaskSchedule.progress(done: subtasks.filter(\.isDone).count, total: subtasks.count)
        if task.dueDate != nil || task.reminderDate != nil || task.pageURL != nil || progress != nil {
            HStack(spacing: 8) {
                if let due = task.dueDate {
                    let status = TaskSchedule.due(due)
                    Label(TaskSchedule.label(for: due), systemImage: "calendar")
                        .foregroundColor(
                            task.isDone ? theme.mutedForeground
                                : status == .overdue ? .red : status == .today ? theme.accent : theme.mutedForeground
                        )
                }
                if let reminder = task.reminderDate, !task.isDone {
                    Label(reminder.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                        .foregroundColor(theme.mutedForeground)
                }
                if let page = task.pageURL {
                    Button {
                        tab.openPeek(page)
                    } label: {
                        Label(page.host() ?? "Page", systemImage: "link")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.accent)
                    .help(task.pageTitle ?? page.absoluteString)
                }
                if let progress {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Label(progress, systemImage: isExpanded ? "chevron.down" : "list.bullet.indent")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.mutedForeground)
                }
            }
            .font(.system(size: 10.5))
            .labelStyle(CompactLabelStyle())
        }
    }

    // MARK: - Subtasks

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(task.orderedSubtasks) { subtask in
                TaskRow(task: subtask, tab: tab, isSubtask: true)
            }
            TextField("Add subtask", text: $newSubtask)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 26)
                .padding(.vertical, 4)
                .onSubmit {
                    tabManager.addSubtask(newSubtask, to: task)
                    newSubtask = ""
                }
        }
        .padding(.leading, 18)
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        Button("Details…") { isShowingDetails = true }
        Button("Rename") { isEditingTitle = true }
        if !isSubtask {
            Button(isExpanded ? "Hide Subtasks" : "Show Subtasks") { isExpanded.toggle() }
        }
        if let page = task.pageURL {
            Button("Open Page") { tab.openPeek(page) }
        } else {
            Button("Attach Current Page") { tabManager.attachPage(of: tab, to: task) }
        }
        Divider()
        Button("Delete", role: .destructive) { tabManager.deleteTask(task) }
    }
}

/// Icon and text close together, for the small badges of a task.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
