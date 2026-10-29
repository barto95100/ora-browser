import SwiftUI

/// The space's tasks, beside the page like the tab's note: added at the top,
/// checked, with their due day, reminder, page and subtasks. Done ones are
/// gathered at the bottom.
struct TasksPanel: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme

    @State private var newTitle = ""
    @State private var showsDone = false
    @FocusState private var isAdding: Bool

    private var space: TabContainer {
        tab.container
    }

    private var openTasks: [SpaceTask] {
        space.tasks.filter { !$0.isDone }.sorted { $0.order < $1.order }
    }

    private var doneTasks: [SpaceTask] {
        space.tasks.filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            addField
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if openTasks.isEmpty {
                        Text(doneTasks.isEmpty ? "No task yet" : "All done")
                            .font(.system(size: 12))
                            .foregroundColor(theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(openTasks) { task in
                        TaskRow(task: task, tab: tab)
                    }
                    if !doneTasks.isEmpty {
                        doneSection
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Tasks")
                    .font(.system(size: 13, weight: .semibold))
                Text(space.name)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                appState.showTasks = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .foregroundColor(theme.foreground.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.mutedForeground)
            TextField("New task", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($isAdding)
                .onSubmit {
                    tabManager.addTask(newTitle, to: space)
                    newTitle = ""
                    isAdding = true
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.mutedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(10)
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsDone.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsDone ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Completed (\(doneTasks.count))")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(theme.mutedForeground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if showsDone {
                ForEach(doneTasks) { task in
                    TaskRow(task: task, tab: tab)
                }
            }
        }
    }
}
