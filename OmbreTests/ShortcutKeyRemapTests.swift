import AppKit
@testable import Ombre
import SwiftUI
import Testing

/// ⌘1…⌘9 and the zoom shortcuts on AZERTY and QWERTY keyboards.
struct ShortcutKeyRemapTests {
    private func remap(_ modifiers: NSEvent.ModifierFlags, _ unshifted: String, _ shifted: String) -> String? {
        ShortcutKeyRemap.character(modifiers: modifiers, unshifted: unshifted, shifted: shifted)
    }

    @Test func azertyDigitKeysStandForTheirDigit() {
        // French AZERTY: & é " ' ( § è ! ç à, digits with ⇧.
        let row = [
            ("&", "1"),
            ("é", "2"),
            ("\"", "3"),
            ("'", "4"),
            ("(", "5"),
            ("§", "6"),
            ("è", "7"),
            ("!", "8"),
            ("ç", "9"),
            ("à", "0")
        ]
        for (unshifted, digit) in row {
            #expect(remap(.command, unshifted, digit) == digit)
        }
    }

    @Test func qwertyKeysAreLeftAsTheyAre() {
        #expect(remap(.command, "1", "!") == nil)
        #expect(remap(.command, "0", ")") == nil)
        #expect(remap(.command, "-", "_") == nil)
        #expect(remap(.command, "t", "T") == nil)
    }

    /// ⌘= zooms in, as ⌘+ (AZERTY and QWERTY both have "=" under "+").
    @Test func equalsStandsForPlus() {
        #expect(remap(.command, "=", "+") == "+")
    }

    /// Other modifiers keep their own keys: ⌃⌘= is Split View, ⌘⇧& types 1.
    @Test func onlyCommandAloneIsRemapped() {
        #expect(remap([.control, .command], "=", "+") == nil)
        #expect(remap([.command, .shift], "&", "1") == nil)
        #expect(remap([.command, .option], "&", "1") == nil)
        #expect(remap([], "&", "1") == nil)
    }

    /// The menus show the digit itself (no remapping by macOS).
    @Test @MainActor func digitShortcutsAreNotLocalized() {
        let tab1 = KeyboardShortcuts.Tabs.tab1.defaultChord.keyboardShortcut
        #expect(String(describing: tab1.localization) == String(describing: KeyboardShortcut.Localization.custom))
        let zoomReset = KeyboardShortcuts.Zoom.reset.defaultChord.keyboardShortcut
        #expect(String(describing: zoomReset.localization) == String(describing: KeyboardShortcut.Localization.custom))
        let newTab = KeyboardShortcuts.Tabs.new.defaultChord.keyboardShortcut
        #expect(String(describing: newTab.localization) == String(describing: KeyboardShortcut.Localization.automatic))
    }
}
