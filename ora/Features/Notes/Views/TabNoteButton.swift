import SwiftUI

/// Address bar button: shows or hides the tab's note beside the page.
struct TabNoteButton: View {
    let foregroundColor: Color
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            appState.showTabNote.toggle()
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appState.showTabNote ? theme.accent : foregroundColor)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.showTabNote ? "Hide Tab Note" : "Tab Note")
        .accessibilityLabel(Text("Tab Note"))
    }
}
