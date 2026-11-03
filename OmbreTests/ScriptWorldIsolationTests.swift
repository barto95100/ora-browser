import Foundation
@testable import Ombre
import Testing
import WebKit

/// The app's scripts run in a world of their own: a page can't see them, use
/// their message handlers or replace their functions (MOT-02, SEC-02).
@MainActor
struct ScriptWorldIsolationTests {
    private func makePage() -> BrowserPage {
        let privacy = SpacePrivacySettings()
        return BrowserPage(
            // Private: nothing written on disk by the test.
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts()
                    + BrowserPrivacyService.privacyScripts(for: privacy, spaceID: UUID(), isPrivate: true),
                privacySettings: privacy,
                enablesWebNotifications: true
            ),
            delegate: nil
        )
    }

    /// Runs `script` as the page itself would.
    private func evaluateInPage(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.extensionWebView.evaluateJavaScript(script, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    /// Runs `script` in the app's world, as the app does.
    private func evaluateInApp(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.evaluateJavaScript(script) { value, _ in continuation.resume(returning: value) }
        }
    }

    /// Loads a secure page and waits for the app's scripts.
    private func load(_ page: BrowserPage) async throws {
        page.extensionWebView.loadHTMLString(
            "<html><body><form><input type='password'></form></body></html>",
            baseURL: URL(string: "https://example.com/")
        )
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if await evaluateInApp(page, "typeof window.__passwordManager") as? String == "object" { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The app's scripts never ran")
    }

    @Test func pageSeesNoneOfTheAppsScripts() async throws {
        let page = makePage()
        defer { page.teardown() }
        try await load(page)

        for name in ["__bridge", "__media", "__mediaInstalled", "__triggerPiP", "__passwordManager"] {
            #expect(await evaluateInPage(page, "typeof window.\(name)") as? String == "undefined", "\(name)")
            #expect(await evaluateInApp(page, "typeof window.\(name)") as? String != "undefined", "\(name)")
        }
        // No global of the page's own world names the app.
        let names = await evaluateInPage(
            page,
            "Object.getOwnPropertyNames(window).filter(n => /^(_*)ombre/i.test(n)).join(',')"
        ) as? String
        #expect(names == "")
        // Nor its DOM.
        #expect(await evaluateInPage(page, "/ombre-|data-ombre/.test(document.documentElement.outerHTML)") as? Bool ==
            false)
    }

    /// The page can't post to the app's handlers (only the notifications
    /// bridge, which gives it the standard API, is in its world).
    @Test func pageCannotReachTheAppsHandlers() async throws {
        let page = makePage()
        defer { page.teardown() }
        try await load(page)

        for name in ["passwordManager", "mediaEvent", "linkHover", "favicon"] {
            let script = "typeof (window.webkit && window.webkit.messageHandlers.\(name))"
            #expect(await evaluateInPage(page, script) as? String == "undefined", "\(name)")
            #expect(await evaluateInApp(page, script) as? String == "object", "\(name)")
        }
        #expect(await evaluateInPage(page, "typeof Notification") as? String == "function")
    }
}
