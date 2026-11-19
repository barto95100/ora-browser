import AppKit
import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// Little Ombre's keys follow the browser window's shortcuts, customized
/// ones included.
@MainActor
struct LittleOmbreKeyTests {
    private func chord(_ key: Character, _ modifiers: EventModifiers = .command) -> KeyChord {
        KeyChord(keyEquivalent: KeyEquivalent(key), modifiers: modifiers)
    }

    @Test func theDefaultsAreTheBrowserWindows() {
        let defaults: @MainActor (KeyboardShortcutDefinition) -> KeyChord = { $0.defaultChord }
        #expect(LittleOmbreKey.key(for: chord("o"), chord: defaults) == .openInOmbre)
        #expect(LittleOmbreKey.key(for: chord("l"), chord: defaults) == .focusAddress)
        // From the menu, not matched here.
        #expect(LittleOmbreKey.key(for: chord("r"), chord: defaults) == nil)
        #expect(LittleOmbreKey.key(for: chord("o", [.command, .shift]), chord: defaults) == nil)
        #expect(LittleOmbreKey.key(for: chord("w"), chord: defaults) == nil)
    }

    /// "Focus Address Bar" moved to ⌘⇧E: ⌘⇧E goes to the address, ⌘L no longer does.
    @Test func aCustomizedShortcutIsFollowed() {
        let custom: @MainActor (KeyboardShortcutDefinition) -> KeyChord = {
            $0.id == KeyboardShortcuts.Address.focus.id
                ? KeyChord(keyEquivalent: KeyEquivalent("e"), modifiers: [.command, .shift])
                : $0.defaultChord
        }
        #expect(LittleOmbreKey.key(for: chord("E", [.command, .shift]), chord: custom) == .focusAddress)
        #expect(LittleOmbreKey.key(for: chord("l"), chord: custom) == nil)
        #expect(LittleOmbreKey.key(for: chord("o"), chord: custom) == .openInOmbre)
    }

    /// The menu's Reload, sent to this Little Ombre only (Back and Forward
    /// go the same way).
    @Test func theMenusReloadReachesItsLittleOmbre() async throws {
        try await TabManagerTestWindow.run { window in
            let little = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
            defer { little.window.close() }
            let page = little.popup.page
            page.extensionWebView.loadHTMLString("<p>1</p>", baseURL: URL(string: "https://example.com/1"))
            await window.waitUntil("loaded") { page.lastCommittedURL != nil && !page.isLoading }

            // Another window's Reload: not this one's.
            NotificationCenter.default.post(name: .reloadPage, object: NSWindow())
            #expect(!page.isLoading)
            NotificationCenter.default.post(name: .reloadPage, object: little.window)
            await window.waitUntil("reloading") { page.isLoading }
        }
    }

    /// ⌘Q typed in a Little Ombre asks the app to quit, page focused or
    /// not, on a QWERTY (Q is key 12) or an AZERTY keyboard (key 0).
    /// Serialized: each case swaps the app's delegate.
    @Test(.serialized, arguments: [UInt16(12), UInt16(0)], [false, true])
    func commandQReachesQuit(keyCode: UInt16, pageFocused: Bool) async throws {
        try await TabManagerTestWindow.run { window in
            let little = try #require(LittleOmbreWindow.open(nil, from: window.tabManager, window: nil))
            defer { little.window.close() }
            if pageFocused { little.window.makeFirstResponder(little.popup.page.webView) }
            // Refuses to quit: only counts the requests. Put back right after.
            let quit = QuitRecorder()
            let appDelegate = NSApp.delegate
            NSApp.delegate = quit
            defer { NSApp.delegate = appDelegate }

            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: little.window.windowNumber, context: nil, characters: "q",
                charactersIgnoringModifiers: "q", isARepeat: false, keyCode: keyCode
            ))
            // As NSApplication does: the key window first, then the menu
            // (its local key monitors aside, not covered here).
            if !little.window.performKeyEquivalent(with: event) {
                _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
            }
            await window.waitUntil("asked to quit") { quit.requests > 0 }
            // A late second request must not reach the app's own delegate.
            try await Task.sleep(for: .milliseconds(200))
            #expect(quit.requests == 1)
            #expect(LittleOmbreWindow.isLittleOmbreWindow(little.window))
        }
    }
}

/// Counts the requests to quit, and refuses them.
@MainActor
private final class QuitRecorder: NSObject, NSApplicationDelegate {
    private(set) var requests = 0

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requests += 1
        return .terminateCancel
    }
}
