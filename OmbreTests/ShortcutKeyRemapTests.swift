import AppKit
import Carbon.HIToolbox
@testable import Ombre
import SwiftUI
import Testing

/// ⌘1…⌘9 and ⌘0 on AZERTY, QWERTY and other keyboards.
struct ShortcutKeyRemapTests {
    private let one = UInt16(kVK_ANSI_1)

    private func remap(_ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16, _ typed: String) -> String? {
        ShortcutKeyRemap.character(modifiers: modifiers, keyCode: keyCode, typed: typed)
    }

    @Test func azertyDigitRowStandsForItsDigits() {
        // French AZERTY: & é " ' ( § è ! ç à, digits with ⇧.
        let row: [(Int, String, String)] = [
            (kVK_ANSI_1, "&", "1"), (kVK_ANSI_2, "é", "2"), (kVK_ANSI_3, "\"", "3"), (kVK_ANSI_4, "'", "4"),
            (kVK_ANSI_5, "(", "5"), (kVK_ANSI_6, "§", "6"), (kVK_ANSI_7, "è", "7"), (kVK_ANSI_8, "!", "8"),
            (kVK_ANSI_9, "ç", "9"), (kVK_ANSI_0, "à", "0")
        ]
        for (keyCode, typed, digit) in row {
            #expect(remap(.command, UInt16(keyCode), typed) == digit)
        }
    }

    /// Czech QWERTZ: the 1 key types "+", as macOS's own renaming does.
    @Test func otherLayoutsWithShiftedDigitsToo() {
        #expect(remap(.command, one, "+") == "1")
    }

    @Test func keysThatTypeTheirDigitAreLeftAsTheyAre() {
        #expect(remap(.command, one, "1") == nil)
        #expect(remap(.command, UInt16(kVK_ANSI_0), "0") == nil)
        #expect(remap(.command, UInt16(kVK_ANSI_T), "t") == nil)
        #expect(remap(.command, UInt16(kVK_ANSI_Equal), "=") == nil)
        #expect(remap([.command, .numericPad], UInt16(kVK_ANSI_Keypad1), "1") == nil)
    }

    /// Other modifiers keep their own keys: ⌘⇧& types 1, ⌃⌘& is not ⌘1.
    @Test func onlyCommandAloneIsRemapped() {
        #expect(remap([.command, .shift], one, "&") == nil)
        #expect(remap([.command, .option], one, "&") == nil)
        #expect(remap([.control, .command], one, "&") == nil)
        #expect(remap([], one, "&") == nil)
    }

    /// The menus show the digit itself (no renaming by macOS).
    @Test @MainActor func digitShortcutsAreNotLocalized() {
        func localization(_ definition: KeyboardShortcutDefinition) -> String {
            String(describing: definition.defaultChord.keyboardShortcut.localization)
        }
        let custom = String(describing: KeyboardShortcut.Localization.custom)
        #expect(localization(KeyboardShortcuts.Tabs.tab1) == custom)
        #expect(localization(KeyboardShortcuts.Zoom.reset) == custom)
        #expect(localization(KeyboardShortcuts.Tabs.new) == String(describing: KeyboardShortcut.Localization.automatic))
    }
}
