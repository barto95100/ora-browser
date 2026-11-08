import AppKit
import Foundation
@testable import Ombre
import Testing
import WebKit

/// The header takes the page's theme color as soon as WebKit reports it,
/// without polling the page while it loads.
@MainActor
struct HeaderColorTests {
    private final class Recorder: BrowserPageDelegate {
        var themeColors: [NSColor?] = []

        func browserPage(_ page: BrowserPage, didChangeThemeColor color: NSColor?) {
            themeColors.append(color)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        // 30 s at most, as soon as it holds: GitHub's runners can be that slow.
        let deadline = Date().addingTimeInterval(30)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A local page declaring a red theme color.
    private func redPage() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeaderColorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("page.html")
        try """
        <html><head><meta name="theme-color" content="#ff0000"></head><body>Red</body></html>
        """.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test func thePageThemeColorIsReported() async throws {
        let file = try redPage()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let recorder = Recorder()
        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(userScripts: [], privacySettings: SpacePrivacySettings()),
            delegate: recorder
        )
        defer { page.teardown() }

        page.load(URLRequest(url: file))
        await waitUntil { recorder.themeColors.contains { $0 != nil } }

        let reported = try #require(recorder.themeColors.compactMap(\.self).last?.usingColorSpace(.sRGB))
        #expect(reported.redComponent > 0.9)
        #expect(reported.greenComponent < 0.1)
        #expect(page.themeColor != nil)
    }

    @Test func theTabsHeaderTakesTheThemeColor() async throws {
        let file = try redPage()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await TabManagerTestWindow.run { window in
            let space = try window.activeSpace
            let tab = window.addUnloadedTab("page", order: 1, in: space)
            let page = tab.makeBrowserPage(isPrivate: true)
            tab.browserPage = page
            tab.setupBrowserPageDelegate(for: page)
            defer {
                tab.destroyWebView()
                BrowserEngine.shared.endPrivateSession(window.tabManager.privateSessionID)
            }

            page.load(URLRequest(url: file))
            await waitUntil { tab.backgroundColorHex.uppercased() == "#FF0000" }

            #expect(tab.backgroundColorHex.uppercased() == "#FF0000")
        }
    }
}
