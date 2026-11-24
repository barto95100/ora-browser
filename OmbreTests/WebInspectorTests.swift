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
        page.webView.configuration.preferences.value(forKey: WebInspector.preferenceKey) as? Bool
    }

    @Test func aPageIsNotInspectableWithTheSettingOff() {
        withInspection(false) {
            let page = makePage()
            #expect(page.webView.isInspectable == false)
            #expect(inspectsElements(page) == false)
            page.teardown()
        }
    }

    /// In Release too ("Inspect Element" was Debug only).
    @Test func anOpenPageFollowsTheSetting() {
        withInspection(false) {
            let page = makePage()
            BrowserEngine.shared.allowsInspection = true
            #expect(page.webView.isInspectable)
            #expect(inspectsElements(page) == true)
            BrowserEngine.shared.allowsInspection = false
            #expect(page.webView.isInspectable == false)
            #expect(inspectsElements(page) == false)
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
        #expect(preferences.value(forKey: WebInspector.preferenceKey) as? Bool == true)
        WebInspector.allowInspectElement(false, in: preferences)
        #expect(preferences.value(forKey: WebInspector.preferenceKey) as? Bool == false)
    }

    /// Fails when a macOS update takes `_inspector`, `show` or `showConsole`
    /// away: View › Developer would quietly do nothing.
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
