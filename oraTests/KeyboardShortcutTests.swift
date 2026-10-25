import AppKit
@testable import Ora
import SwiftUI
import Testing

struct KeyboardShortcutTests {
    private func keyDown(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @Test func controlCommandFMatchesTheDefaultFullScreenShortcut() throws {
        let event = try keyDown("f", keyCode: 3, modifiers: [.control, .command])

        #expect(KeyChord(fromEvent: event) == KeyboardShortcuts.Window.fullscreen.defaultChord)
    }

    @Test func commandFAloneIsNotTheFullScreenShortcut() throws {
        let event = try keyDown("f", keyCode: 3, modifiers: [.command])

        #expect(KeyChord(fromEvent: event) != KeyboardShortcuts.Window.fullscreen.defaultChord)
    }
}
