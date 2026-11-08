import Foundation
import ObjectiveC
@testable import Ombre
import Testing
import WebKit

/// The site's location permission (MOT-25, decided by Ludo): asked like the
/// camera, remembered per site in its space.
struct GeolocationPermissionTests {
    private static let privateSelector =
        NSSelectorFromString("_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:")

    /// Before macOS 27, WebKit only asks through this private delegate
    /// method: fails when a WebKit drops it (the location would then be
    /// refused to every site).
    @Test func webKitStillAsksThroughItsDelegate() throws {
        let declared: Bool
        if #available(macOS 27.0, *) {
            declared = true
        } else {
            let proto = try #require(objc_getProtocol("WKUIDelegatePrivate"))
            declared = protocol_getMethodDescription(proto, Self.privateSelector, false, true).name != nil
        }
        #expect(declared)
    }

    /// macOS 27's public method: its Swift name must match WebKit's
    /// selector exactly (a near miss only warns, and is never called).
    @Test func pageImplementsMacOS27sMethod() throws {
        let selector =
            NSSelectorFromString("webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:")
        #expect(BrowserPage.instancesRespond(to: selector))
        if #available(macOS 27.0, *) {
            let proto = try #require(objc_getProtocol("WKUIDelegate"))
            #expect(protocol_getMethodDescription(proto, selector, false, true).name != nil)
        }
    }

    @MainActor
    @Test func pageAnswersWebKitsQuestion() {
        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: [],
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: false
            ),
            delegate: nil
        )
        defer { page.teardown() }
        #expect(page.responds(to: Self.privateSelector))
    }

    @Test func locationIsItsOwnPermission() throws {
        #expect(BrowserPermissionKind.geolocation.sitePermissionTypes == [.location])
        var permissions = SitePermissions()
        permissions[.location] = .allow
        #expect(permissions.decision(for: [.location]) == .allow)
        #expect(permissions.decision(for: [.camera]) == .ask)
        // Saved before it existed: asks.
        let older = try JSONDecoder().decode(SitePermissions.self, from: Data(#"{"camera":"allow"}"#.utf8))
        #expect(older.location == .ask)
        #expect(SitePermissionType.location.title == "Location")
    }
}
