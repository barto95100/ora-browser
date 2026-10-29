import SwiftUI

/// Sidebar bottom button for today's browsing time beside the page, next to
/// notes and tasks (the large panel without a page).
struct SidebarTimeButton: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.toggleTimeSummary(hasPage: tabManager.activeTab != nil)
        } label: {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(appState.showTimeSummary ? theme.accent : .secondary)
                .frame(width: 28, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Browsing Time (⌥⌘Y)")
    }
}

extension AppState {
    /// The summary beside the page, or the large panel without a page.
    func toggleTimeSummary(hasPage: Bool) {
        if hasPage {
            showTimeSummary.toggle()
        } else {
            showLauncher = false
            showHistory = false
            showNotes = false
            showTime.toggle()
        }
    }
}
