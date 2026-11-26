import SwiftUI

/// The address bar's reader button, like Safari's: shown when the page
/// looks like an article, filled while reader mode is on.
struct ReaderButton: View {
    let page: BrowserPage
    let foregroundColor: Color
    /// The shortcut as customized, in the tooltip.
    @ObservedObject private var shortcuts = CustomKeyboardShortcutManager.shared

    private var help: String {
        let chord = KeyboardShortcuts.Page.reader.currentChord.display
        return page.reader.isShown
            ? String(localized: "Close Reader (\(chord))")
            : String(localized: "Show Reader (\(chord))")
    }

    var body: some View {
        if page.reader.isAvailable || page.reader.isShown {
            Button {
                page.reader.toggle(page)
            } label: {
                Image(systemName: page.reader.isShown ? "doc.plaintext.fill" : "doc.plaintext")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(foregroundColor)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .disabled(page.reader.isOpening)
        }
    }
}
