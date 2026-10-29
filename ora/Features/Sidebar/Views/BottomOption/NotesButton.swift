import SwiftUI

/// Opens the space's notes (see `NotesPanel`), next to the downloads.
struct NotesButton: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.showLauncher = false
            appState.showHistory = false
            appState.showNotes.toggle()
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.1) : .clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Notes (⌥⌘N)")
    }
}
