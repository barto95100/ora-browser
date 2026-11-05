import Foundation
@testable import Ombre
import Testing
import WebKit

/// Pages are inspectable only with the "Allow Web Inspector" setting on, and
/// follow it while open.
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

    @Test func aPageIsNotInspectableWithTheSettingOff() {
        withInspection(false) {
            let page = makePage()
            #expect(page.webView.isInspectable == false)
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
