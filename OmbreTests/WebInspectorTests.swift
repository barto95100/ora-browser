import AppKit
import Foundation
@testable import Ombre
import Testing
import WebKit

/// Pages are inspectable only with the "Allow Web Inspector" setting on, and
/// follow it while open: in Ombre ("Inspect Element", View › Developer, see
/// `WebInspector`, private WebKit API tolerated in CLAUDE.md) and from
/// Safari's Develop menu. Nothing is opened: no window may show while the
/// tests run.
@MainActor
@Suite(.serialized)
struct WebInspectorTests {
    private func makePage() -> BrowserPage {
        BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(userScripts: [], privacySettings: SpacePrivacySettings()),
            delegate: nil
        )
    }

    private func withInspection(_ allowed: Bool, _ body: () -> Void) {
        // Created first: its start sets the engine from the stored setting.
        _ = SettingsStore.shared
        let engine = BrowserEngine.shared
        let previous = engine.allowsInspection
        engine.allowsInspection = allowed
        defer { engine.allowsInspection = previous }
        body()
    }

    /// "Inspect Element" in the page's context menu (the private preference).
    private func inspectsElements(_ page: BrowserPage) -> Bool? {
        WebInspector.inspectsElements(in: page.webView.configuration.preferences)
    }

    @Test func aPageIsNotInspectableWithTheSettingOff() {
        withInspection(false) {
            let page = makePage()
            #expect(page.webView.isInspectable == false)
            #expect(inspectsElements(page) == false)
            page.teardown()
        }
    }

    @Test func anOpenPageFollowsTheSetting() {
        withInspection(false) {
            let page = makePage()
            BrowserEngine.shared.allowsInspection = true
            #expect(page.webView.isInspectable)
            BrowserEngine.shared.allowsInspection = false
            #expect(page.webView.isInspectable == false)
            page.teardown()
        }
    }

    @Test func aTornDownPageNoLongerFollowsIt() {
        withInspection(false) {
            let page = makePage()
            page.teardown()
            BrowserEngine.shared.allowsInspection = true
            #expect(page.webView.isInspectable == false)
            #expect(inspectsElements(page) == false)
        }
    }

    /// Fails when a macOS update takes the preference away: "Inspect Element"
    /// would quietly leave the context menu.
    @Test func webKitStillHasTheInspectElementPreference() {
        let preferences = WKPreferences()
        #expect(WebInspector.hasPreference(in: preferences))
        WebInspector.allowInspectElement(true, in: preferences)
        #expect(WebInspector.inspectsElements(in: preferences) == true)
        WebInspector.allowInspectElement(false, in: preferences)
        #expect(WebInspector.inspectsElements(in: preferences) == false)
    }

    /// In Release too ("Inspect Element" was Debug only), except in private
    /// windows: Safari's Develop menu only there (the inspector in Ombre
    /// would keep the console's history on the disk). The pages of these
    /// tests are private: a regular one would write its data on the disk.
    @Test func aPrivatePageIsNotInspectedInOmbre() {
        #expect(BrowserPage.inspectsInOmbre(isPrivate: false))
        #expect(!BrowserPage.inspectsInOmbre(isPrivate: true))
        withInspection(true) {
            let page = makePage()
            #expect(page.webView.isInspectable)
            #expect(inspectsElements(page) == false)
            page.teardown()
        }
    }

    /// Fails when a macOS update takes `_inspector`, `show`, `showConsole`,
    /// `close` or `isVisible` away: View › Developer would quietly do nothing.
    @Test func webKitCanStillShowTheInspectorAndItsConsole() {
        #expect(WebInspector.canShowPanels)
    }

    /// ⌥⌘I and ⌥⌘C, like Safari, taken by no other shortcut.
    @Test func theShortcutsAreSafarisAndFree() {
        let inspector = KeyboardShortcuts.Developer.webInspector
        let console = KeyboardShortcuts.Developer.javaScriptConsole
        #expect(inspector.defaultChord == KeyChord(keyEquivalent: .init("i"), modifiers: [.command, .option]))
        #expect(console.defaultChord == KeyChord(keyEquivalent: .init("c"), modifiers: [.command, .option]))
        for shortcut in [inspector, console] {
            let other = KeyboardShortcuts.conflict(
                for: shortcut.defaultChord, excluding: shortcut.id, chord: { $0.defaultChord }
            )
            #expect(other == nil)
        }
    }

    /// WebKit took ⌥⌘C for ⌘C (Copy) before the menu: the Developer keys go
    /// to the menu first, on any layout (a US or AZERTY Mac sends "ç" or
    /// "©" for ⌥C, the same "c" without modifiers).
    @Test func theDeveloperKeysGoToTheMenuBeforeThePage() throws {
        for typed in ["ç", "©"] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                windowNumber: 0, context: nil, characters: typed, charactersIgnoringModifiers: "c",
                isARepeat: false, keyCode: 8
            ))
            let chord = try #require(KeyChord(fromEvent: event))
            #expect(ShortcutOverrideMonitor.goesFirstToApp(chord, inspectorAllowed: true, chord: { $0.defaultChord }))
            // Setting off: the page gets them, as any key.
            #expect(!ShortcutOverrideMonitor.goesFirstToApp(chord, inspectorAllowed: false, chord: { $0.defaultChord }))
        }
        let inspector = KeyboardShortcuts.Developer.webInspector.defaultChord
        #expect(ShortcutOverrideMonitor.goesFirstToApp(inspector, inspectorAllowed: true, chord: { $0.defaultChord }))
        // Customized: the new keys, no longer ⌥⌘C.
        let custom = KeyChord(keyEquivalent: .init("j"), modifiers: [.command, .shift])
        let customized: @MainActor (KeyboardShortcutDefinition) -> KeyChord = {
            $0.id == KeyboardShortcuts.Developer.javaScriptConsole.id ? custom : $0.defaultChord
        }
        let console = KeyboardShortcuts.Developer.javaScriptConsole.defaultChord
        #expect(ShortcutOverrideMonitor.goesFirstToApp(custom, inspectorAllowed: true, chord: customized))
        #expect(!ShortcutOverrideMonitor.goesFirstToApp(console, inspectorAllowed: true, chord: customized))
        // Copy itself still goes to the page.
        let copy = KeyChord(keyEquivalent: .init("c"), modifiers: [.command])
        #expect(!ShortcutOverrideMonitor.goesFirstToApp(copy, inspectorAllowed: true, chord: { $0.defaultChord }))
    }

    /// Only from a page: the shortcut recorder and text fields get the keys
    /// as usual.
    @Test func theDeveloperKeysSkipAheadOnlyFromAPage() {
        let page = makePage()
        let child = NSView()
        page.webView.addSubview(child)
        #expect(ShortcutOverrideMonitor.isInPage(page.webView))
        #expect(ShortcutOverrideMonitor.isInPage(child))
        #expect(!ShortcutOverrideMonitor.isInPage(NSTextField()))
        #expect(!ShortcutOverrideMonitor.isInPage(nil))
        page.teardown()
    }

    /// ⌥⌘I and ⌥⌘C open and close the inspector, like Safari.
    @Test func theDeveloperKeysOpenAndClose() {
        // Closed: each opens its panel.
        #expect(WebInspector.action(for: .inspector, isVisible: false, lastShown: nil) == .show(.inspector))
        #expect(WebInspector.action(for: .console, isVisible: false, lastShown: .console) == .show(.console))
        // Open: ⌥⌘I closes it, whatever it shows.
        #expect(WebInspector.action(for: .inspector, isVisible: true, lastShown: .console) == .close)
        #expect(WebInspector.action(for: .inspector, isVisible: true, lastShown: nil) == .close)
        // Open on the console: ⌥⌘C closes it; on another panel: to the console.
        #expect(WebInspector.action(for: .console, isVisible: true, lastShown: .console) == .close)
        #expect(WebInspector.action(for: .console, isVisible: true, lastShown: .inspector) == .show(.console))
        // Opened by "Inspect Element" (Ombre opened nothing): to the console.
        #expect(WebInspector.action(for: .console, isVisible: true, lastShown: nil) == .show(.console))
    }

    @Test func javaScriptIsSetWithThePublicPreference() {
        let page = makePage()
        #expect(page.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(page.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically == false)
        page.teardown()
    }

    @Test func theSettingIsOnByDefaultInDebugBuilds() {
        // The tests run a Debug build (off in Release, like Safari).
        #expect(SettingsStore.developerToolsDefault)
    }
}
