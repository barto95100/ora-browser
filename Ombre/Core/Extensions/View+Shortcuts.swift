import SwiftUI

/// Attach app shortcuts that update as overrides change.
private struct OmbreKeyboardShortcutModifier: ViewModifier {
    let shortcut: KeyboardShortcutDefinition
    @EnvironmentObject private var shortcutManager: CustomKeyboardShortcutManager

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(shortcut.keyboardShortcut)
    }
}

/// Attach a tooltip that includes the current shortcut display.
private struct OmbreShortcutHelpModifier: ViewModifier {
    let helpText: String
    let shortcut: KeyboardShortcutDefinition
    @EnvironmentObject private var shortcutManager: CustomKeyboardShortcutManager

    func body(content: Content) -> some View {
        content
            .help("\(helpText) (\(shortcut.currentChord.display))")
    }
}

extension View {
    /// Use in place of `.keyboardShortcut` to auto-update on custom shortcut changes.
    func ombreShortcut(_ shortcut: KeyboardShortcutDefinition) -> some View {
        modifier(OmbreKeyboardShortcutModifier(shortcut: shortcut))
    }

    /// Helper to keep tooltips in sync with the current shortcut mapping.
    /// Results in a tooltip like: "Copy URL (⇧⌘C)"
    func ombreShortcutHelp(_ helpText: String, for shortcut: KeyboardShortcutDefinition) -> some View {
        modifier(OmbreShortcutHelpModifier(helpText: helpText, shortcut: shortcut))
    }
}
