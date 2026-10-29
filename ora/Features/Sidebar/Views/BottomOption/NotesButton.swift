import SwiftUI

/// The tab's note beside the page, like the tasks and the time (all the
/// space's notes, `NotesPanel`, open from it or without a page).
struct NotesButton: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.toggleTabNote(hasPage: tabManager.activeTab != nil)
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(appState.showTabNote ? theme.accent : .secondary)
                .frame(width: 28, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Notes (⌥⌘N)")
    }
}

extension AppState {
    /// The tab's note beside the page, or all the notes without a page.
    func toggleTabNote(hasPage: Bool) {
        if hasPage {
            showTabNote.toggle()
        } else {
            showLauncher = false
            showHistory = false
            showTime = false
            showNotes.toggle()
        }
    }
}
