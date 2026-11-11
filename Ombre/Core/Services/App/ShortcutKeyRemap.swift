import AppKit

/// Shortcuts with digits work and show as in Safari on every keyboard layout.
///
/// The menus show ⌘1…⌘9 and ⌘0 as they are (macOS would otherwise rename them
/// after the key in the same place, ⌘& ⌘é… on a French keyboard). On a layout
/// where digits need ⇧ (AZERTY), ⌘ and the key of a digit then means that
/// digit, like in Safari; ⌘= means ⌘+ (zoom in), as on a US keyboard.
enum ShortcutKeyRemap {
    /// The character a ⌘ press stands for, or nil to leave it as is.
    /// `unshifted` / `shifted`: what the key types without and with ⇧.
    static func character(
        modifiers: NSEvent.ModifierFlags,
        unshifted: String?,
        shifted: String?
    ) -> String? {
        // ⌘ alone: ⌃⌘= (Split View) and ⌘⇧… keep their own keys.
        guard modifiers.intersection([.command, .option, .control, .shift]) == .command,
              let unshifted, let shifted, unshifted != shifted
        else { return nil }
        if shifted.count == 1, shifted.first?.isASCII == true, shifted.first?.isNumber == true,
           unshifted.first?.isNumber != true
        {
            return shifted
        }
        if unshifted == "=", shifted == "+" {
            return "+"
        }
        return nil
    }

    /// `event` with the character it stands for, or nil if none.
    static func remapped(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              let character = character(
                  modifiers: event.modifierFlags,
                  unshifted: event.characters(byApplyingModifiers: []),
                  shifted: event.characters(byApplyingModifiers: .shift)
              ),
              event.charactersIgnoringModifiers != character
        else { return nil }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        )
    }
}
