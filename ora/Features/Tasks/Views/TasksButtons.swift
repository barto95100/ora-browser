import SwiftUI

/// Address bar button: shows or hides the space's tasks beside the page.
struct TasksButton: View {
    let foregroundColor: Color
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            appState.showTasks.toggle()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appState.showTasks ? theme.accent : foregroundColor)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.showTasks ? "Hide Tasks" : "Tasks (⌥⌘T)")
        .accessibilityLabel(Text("Tasks"))
    }
}

/// Sidebar bottom button for the space's tasks, next to the notes.
struct SidebarTasksButton: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.showTasks.toggle()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(appState.showTasks ? theme.accent : .secondary)
                .frame(width: 28, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(tabManager.activeTab == nil)
        .onHover { isHovering = $0 }
        .help("Tasks (⌥⌘T)")
    }
}
