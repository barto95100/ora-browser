import Foundation
@testable import Ombre
import Testing
import WebKit

/// "Clear cookies / cache for this site": the site's own data, in the tab's
/// own store.
@MainActor
struct ClearSiteDataTests {
    @Test(arguments: [
        ("x.fr", "www.x.fr", true),
        ("google.com", "mail.google.com", true),
        ("example.com", "example.com", true),
        ("Example.com", "EXAMPLE.com", true),
        // A mere substring is another site.
        ("box.com", "x.com", false),
        ("x.com", "box.com", false),
        ("google.com", "notgoogle.com", false)
    ])
    func aRecordBelongsToItsSiteOnly(name: String, host: String, matches: Bool) {
        #expect(BrowserEngineProfile.isRecord(named: name, of: host) == matches)
    }

    @Test func clearingASiteKeepsTheOthers() async throws {
        let window = UUID()
        defer { BrowserEngine.shared.endPrivateSession(window) }
        let profile = BrowserEngine.shared.makeProfile(identifier: UUID(), isPrivate: true, privateSession: window)
        let page = BrowserPage(
            profile: profile,
            configuration: .ombreDefault(userScripts: [], privacySettings: SpacePrivacySettings()),
            delegate: nil
        )
        defer { page.teardown() }
        let cookies = profile.dataStore.httpCookieStore
        for domain in ["www.x.com", "box.com"] {
            let cookie = try #require(HTTPCookie(properties: [
                .domain: domain, .path: "/", .name: "session", .value: "1",
                .expires: Date().addingTimeInterval(3600)
            ]))
            await cookies.setCookie(cookie)
        }

        await withCheckedContinuation { continuation in
            page.clearWebsiteData(ofTypes: [.cookies], forHost: "www.x.com") { continuation.resume() }
        }

        let left = await cookies.allCookies().map(\.domain)
        #expect(!left.contains("www.x.com"))
        // Before, nothing was cleared ("x.com" doesn't contain "www.x.com"),
        // and clearing "x.com" also cleared "box.com" (a substring).
        #expect(left.contains("box.com"))
    }

    @Test func aTabsSiteIsClearedInItsOwnSession() async throws {
        try await TabManagerTestWindow.run { window in
            let space = window.createSpace("Private")
            let tab = window.addUnloadedTab("page", order: 1, in: space)
            tab.browserPage = tab.makeBrowserPage(isPrivate: true)
            defer {
                tab.browserPage?.teardown()
                BrowserEngine.shared.endPrivateSession(window.tabManager.privateSessionID)
            }
            let store = try #require(tab.browserPage?.webView.configuration.websiteDataStore)
            let cookie = try #require(HTTPCookie(properties: [
                .domain: "x.com", .path: "/", .name: "session", .value: "1",
                .expires: Date().addingTimeInterval(3600)
            ]))
            let other = try #require(HTTPCookie(properties: [
                .domain: "box.com", .path: "/", .name: "session", .value: "1",
                .expires: Date().addingTimeInterval(3600)
            ]))
            await store.httpCookieStore.setCookie(cookie)
            await store.httpCookieStore.setCookie(other)

            await withCheckedContinuation { continuation in
                PrivacyService.clearCookiesForHost(for: "x.com", tab: tab) { continuation.resume() }
            }

            let left = await store.httpCookieStore.allCookies().map(\.domain)
            #expect(!left.contains { $0.hasSuffix("x.com") && !$0.hasSuffix("box.com") })
            // "x.com" is not "box.com".
            #expect(left.contains { $0.hasSuffix("box.com") })
        }
    }
}
