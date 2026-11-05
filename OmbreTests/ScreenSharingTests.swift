import Foundation
import ObjectiveC
@testable import Ombre
import Testing
import WebKit

/// Screen sharing needs WebKit's private setting and delegate method on
/// macOS (the second exception in CLAUDE.md): these fail when a macOS update
/// takes either away, as sharing would then quietly stop working.
struct ScreenSharingTests {
    /// On by default (never set by Ombre): fails if WebKit drops it or
    /// turns it off.
    @Test func webKitStillHasTheSettingOn() {
        #expect(ScreenSharing.isEnabled(in: WKPreferences()))
    }

    @Test func webKitStillAsksThroughItsDelegate() throws {
        let proto = try #require(objc_getProtocol("WKUIDelegatePrivate"))
        let method = protocol_getMethodDescription(proto, ScreenSharing.delegateSelector, false, true)
        #expect(method.name != nil)
        // Four objects and a Boolean, then the answer (an integer, see `ScreenSharing.Decision`).
        #expect(method.types.map { String(cString: $0) }?.contains("B") == true)
    }

    @MainActor
    @Test func pageAnswersWebKitsQuestion() {
        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: [], privacySettings: SpacePrivacySettings(), enablesWebNotifications: false
            ),
            delegate: nil
        )
        defer { page.teardown() }
        #expect(page.responds(to: ScreenSharing.delegateSelector))
        #expect(ScreenSharing.isEnabled(in: page.extensionWebView.configuration.preferences))
    }

    @Test func screenIsItsOwnPermission() throws {
        #expect(BrowserPermissionKind.screen.sitePermissionTypes == [.screen])
        let older = try JSONDecoder().decode(SitePermissions.self, from: Data(#"{"location":"allow"}"#.utf8))
        #expect(older.screen == .ask)
        #expect(SitePermissionType.screen.title == "Screen Sharing")
    }
}
