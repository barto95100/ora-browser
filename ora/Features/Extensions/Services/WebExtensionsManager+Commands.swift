import AppKit
@preconcurrency import WebKit

/// The extensions' keyboard shortcuts (`commands` in their manifest), in
/// normal windows; Ora's own shortcuts come first.
@available(macOS 15.4, *)
extension WebExtensionsManager {
    func handleShortcut(_ event: NSEvent) -> NSEvent? {
        guard BrowserWindows.isNormal(event.window), !Self.menuHasShortcut(for: event) else { return event }
        for item in loadedContexts {
            guard let command = item.context.command(for: event) else { continue }
            // "Open the popup" shows it under the extension's button.
            popupAnchor = buttonAnchors.object(forKey: item.record.id as NSString)
            item.context.performCommand(command)
            return nil
        }
        return event
    }

    /// The shortcut as shown in menus, such as ⇧⌘Y.
    static func display(_ command: WKWebExtension.Command) -> String? {
        guard let key = command.activationKey, !key.isEmpty else { return nil }
        return ShortcutText.text(key: key, modifiers: command.modifierFlags)
    }

    /// Whether one of Ora's menus already uses this key.
    private static func menuHasShortcut(for event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased(), let menu = NSApp.mainMenu else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        func search(_ menu: NSMenu) -> Bool {
            menu.items.contains { item in
                if !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key,
                   item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == modifiers
                {
                    return true
                }
                return item.submenu.map(search) ?? false
            }
        }
        return search(menu)
    }
}

/// A shortcut in the macOS way (⌃⌥⇧⌘ then the key).
enum ShortcutText {
    static func text(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }
}
