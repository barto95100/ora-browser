import AppKit
import Foundation
@testable import Ombre
import Testing
import WebKit

/// Picture in Picture needs WebKit's private setting on macOS (see
/// `PictureInPicturePreference`, the one tolerated in CLAUDE.md).
@MainActor
struct PictureInPicturePreferenceTests {
    /// Fails when a macOS update takes the setting away: Picture in Picture
    /// would then quietly stop working.
    @Test func webKitStillHasTheSetting() {
        let preferences = WKPreferences()
        #expect(PictureInPicturePreference.isAvailable(in: preferences))
        PictureInPicturePreference.enable(in: preferences)
        #expect(preferences.value(forKey: PictureInPicturePreference.key) as? Bool == true)
    }

    private func evaluate(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.evaluateJavaScript(script) { value, _ in continuation.resume(returning: value) }
        }
    }

    private func waitFor(_ page: BrowserPage, _ script: String, toBe expected: String) async throws -> String? {
        var value: String?
        for _ in 0 ..< 50 {
            value = await evaluate(page, script) as? String
            if value == expected { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        return value
    }

    /// A playing video with sound: switching tabs asks for Picture in
    /// Picture (`__triggerPiP`), and WebKit takes the request. Without the
    /// setting it refused at once: "NotSupportedError" (#104 took it away).
    @Test func playingVideoIsAcceptedForPictureInPicture() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = try #require(Bundle(for: BundleToken.self).url(
            forResource: "PictureInPictureTest",
            withExtension: "mp4"
        ))
        try FileManager.default.copyItem(at: video, to: folder.appendingPathComponent("video.mp4"))
        let html = folder.appendingPathComponent("index.html")
        try "<html><body><video src='video.mp4' width=64 height=48 loop></video></body></html>"
            .write(to: html, atomically: true, encoding: .utf8)

        let page = BrowserPage(
            // Private: nothing written on disk by the test.
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: false
            ),
            delegate: nil
        )
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = page.contentView
        // Never shown: the tests check that no window is (`TestHostIsolationTests`).
        defer {
            page.teardown()
            window.close()
        }
        page.extensionWebView.loadFileURL(html, allowingReadAccessTo: folder)
        #expect(try await waitFor(page, "typeof window.__triggerPiP", toBe: "function") == "function")

        _ = await evaluate(page, "document.querySelector('video').play(); true")
        #expect(try await waitFor(page, "String(!document.querySelector('video').paused)", toBe: "true") == "true")
        // What the request answers: refused at once without the setting.
        _ = await evaluate(page, """
        const original = HTMLVideoElement.prototype.requestPictureInPicture;
        window.pipAnswer = 'not asked';
        HTMLVideoElement.prototype.requestPictureInPicture = function () {
            window.pipAnswer = 'pending';
            return original.call(this)
                .then((result) => { window.pipAnswer = 'opened'; return result; })
                .catch((error) => { window.pipAnswer = error.name; throw error; });
        };
        true
        """)

        _ = await evaluate(page, "window.__triggerPiP(); true")
        try await Task.sleep(for: .milliseconds(500))

        let answer = await evaluate(page, "window.pipAnswer") as? String
        #expect(answer == "pending" || answer == "opened", "Picture in Picture answered \(answer ?? "nil")")
        _ = await evaluate(page, "document.exitPictureInPicture().catch(() => {}); true")
    }
}

private final class BundleToken {}
