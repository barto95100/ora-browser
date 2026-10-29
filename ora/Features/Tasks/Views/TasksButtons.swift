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
