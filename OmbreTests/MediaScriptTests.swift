import Foundation
@testable import Ombre
import Testing
import WebKit

/// The media script (`OmbreBrowserScripts`): media events heard on the
/// document, no scan of the page, next/previous only on known players
/// (MOT-17, PERF-13).
@MainActor
struct MediaScriptTests {
    private struct Event: Decodable, Equatable {
        let type: String
        var hasNext: Bool?
        var hasPrevious: Bool?
    }

    private func makePage() -> BrowserPage {
        let privacy = SpacePrivacySettings()
        return BrowserPage(
            // Private: nothing written on disk by the test.
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: privacy,
                enablesWebNotifications: false
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

    /// Runs `script` in the app's world, where the media script lives.
    private func evaluateInApp(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.evaluateJavaScript(script) { value, _ in continuation.resume(returning: value) }
        }
    }

    /// Loads `body` and records what the media script tells the app.
    private func load(_ page: BrowserPage, body: String) async throws {
        page.extensionWebView.loadHTMLString(
            "<html><body>\(body)</body></html>",
            baseURL: URL(string: "https://example.com/")
        )
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if await evaluateInApp(page, "typeof window.__media") as? String == "object" {
                _ = await evaluateInApp(page, """
                window.__events = [];
                window.__bridge.postMessage = (name, payload) => {
                  if (name === 'mediaEvent') window.__events.push(JSON.parse(payload));
                  return true;
                };
                true
                """)
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The media script never ran")
    }

    private func events(of page: BrowserPage) async -> [Event] {
        guard let json = await evaluateInApp(page, "JSON.stringify(window.__events || [])") as? String else {
            return []
        }
        return (try? JSONDecoder().decode([Event].self, from: Data(json.utf8))) ?? []
    }

    /// Waits until the recorded events satisfy `condition`, or 2 s.
    private func waitForEvents(of page: BrowserPage, _ condition: ([Event]) -> Bool) async throws -> [Event] {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        var current = await events(of: page)
        while !condition(current), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            current = await events(of: page)
        }
        return current
    }

    /// Waits past the script's 250 ms coalescing, for "nothing happened" checks.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(600))
    }

    /// A medium added by the page is heard from its first event, without
    /// waiting for a scan of the page (there is none any more).
    @Test func mediaAddedByThePageIsHeardAtOnce() async throws {
        let page = makePage()
        defer { page.teardown() }
        try await load(page, body: "")

        _ = await evaluateInPage(page, """
        const audio = document.createElement('audio');
        document.body.appendChild(audio);
        audio.dispatchEvent(new Event('play'));
        true
        """)

        let events = try await waitForEvents(of: page) { $0.contains { $0.type == "state" } }
        #expect(events.contains { $0.type == "state" })
    }

    /// A carousel's or a form's "Next" is not the next track.
    @Test func genericNextButtonIsNotATrackControl() async throws {
        let page = makePage()
        defer { page.teardown() }
        try await load(page, body: """
        <button aria-label="Next">Next</button><button title="Previous">Previous</button><audio></audio>
        """)

        _ = await evaluateInPage(page, "document.querySelector('audio').dispatchEvent(new Event('play')); true")
        _ = try await waitForEvents(of: page) { $0.contains { $0.type == "state" } }
        try await settle()

        #expect(await !events(of: page).contains { $0.hasNext == true || $0.hasPrevious == true })
        #expect(await evaluateInApp(page, "window.__media.next()") as? Bool == false)
        #expect(await evaluateInApp(page, "window.__media.previous()") as? Bool == false)
    }

    /// A known player's buttons are found when its media plays.
    @Test func knownPlayerButtonsAreFound() async throws {
        let page = makePage()
        defer { page.teardown() }
        try await load(page, body: """
        <button class="ytp-prev-button"></button><button class="ytp-next-button"></button><video></video>
        """)

        _ = await evaluateInPage(page, "document.querySelector('video').dispatchEvent(new Event('play')); true")

        let events = try await waitForEvents(of: page) { $0.contains { $0.type == "caps" } }
        #expect(events.contains(Event(type: "caps", hasNext: true, hasPrevious: true)))
    }

    /// Loads two audios that started playing, the first one heard (the
    /// script's own mark, in the app's world: test media can't really play).
    private func loadHeardAndPreview(_ page: BrowserPage) async throws -> [Event] {
        try await load(page, body: "<div id='a'><audio id='one'></audio></div><audio id='two'></audio>")
        _ = await evaluateInApp(page, "document.getElementById('one').__wasPlayed = true; true")
        _ = await evaluateInPage(page, """
        document.querySelectorAll('audio').forEach((audio) => audio.dispatchEvent(new Event('play')));
        true
        """)
        return try await waitForEvents(of: page) { $0.count(where: { $0.type == "state" }) == 2 }
    }

    /// The session ends with the last medium heard, not with a preview
    /// leaving the page; a medium moved within the page stays.
    @Test func sessionEndsWithTheLastMediumHeard() async throws {
        let page = makePage()
        defer { page.teardown() }
        let played = try await loadHeardAndPreview(page)

        // Moved: removed then added back at once.
        _ = await evaluateInPage(page, "document.body.appendChild(document.getElementById('one')); true")
        try await settle()
        #expect(await events(of: page) == played)

        _ = await evaluateInPage(page, "document.getElementById('two').remove(); true")
        let afterPreview = try await waitForEvents(of: page) { $0.count > played.count }
        #expect(afterPreview.last?.type == "state")

        _ = await evaluateInPage(page, "document.getElementById('one').remove(); true")
        let afterLast = try await waitForEvents(of: page) { $0.last?.type == "removed" }
        #expect(afterLast.last?.type == "removed")
    }

    /// A muted preview left on the page doesn't keep the session of the
    /// medium heard.
    @Test func previewLeftBehindDoesNotKeepTheSession() async throws {
        let page = makePage()
        defer { page.teardown() }
        let played = try await loadHeardAndPreview(page)

        _ = await evaluateInPage(page, "document.getElementById('one').remove(); true")
        let after = try await waitForEvents(of: page) { $0.count > played.count }
        #expect(after.last?.type == "removed")
    }
}
