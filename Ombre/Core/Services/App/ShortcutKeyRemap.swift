import AppKit
import Carbon.HIToolbox

/// Shortcuts with digits work and show as in Safari on every keyboard layout.
///
/// The menus show ⌘1…⌘9 and ⌘0 as they are (macOS would otherwise rename them
/// after the key in the same place, ⌘& ⌘é… on a French keyboard). ⌘ and a key
/// of the digit row that doesn't type its digit (AZERTY: & é " …) then stands
/// for that digit, as macOS does for the shortcuts it renames.
enum ShortcutKeyRemap {
    /// The digit of each key of the digit row (US positions).
    private static let digitRow: [UInt16: String] = [
        UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_0): "0"
    ]

    /// The digit a press stands for, or nil to leave it as is.
    /// `typed`: what the key types without ⇧.
    static func character(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, typed: String?) -> String? {
        // ⌘ alone: ⌘⇧, ⌃⌘… keep their own keys.
        guard modifiers.intersection([.command, .option, .control, .shift]) == .command,
              !modifiers.contains(.numericPad),
              let digit = digitRow[keyCode],
              typed?.first?.isNumber != true
        else { return nil }
        return digit
    }

    /// `event` with the digit it stands for, or nil if none.
    static func remapped(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              let character = character(
                  modifiers: event.modifierFlags,
                  keyCode: event.keyCode,
                  typed: event.characters(byApplyingModifiers: [])
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
