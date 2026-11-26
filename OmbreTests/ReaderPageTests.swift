import Foundation
@testable import Ombre
import Testing
import WebKit

/// Reader mode on a real page (private: nothing on disk, no window): a page
/// that changes its address without loading, Find in the article, and
/// ⌘+ / ⌘− / ⌘0 on its text size.
@MainActor
@Suite(.serialized)
struct ReaderPageTests {
    private static let paragraph = """
    The council met on Tuesday evening to discuss the new plan for the river banks, which has been debated \
    for months, and residents came in numbers to hear what would change for them, their streets and their homes.
    """

    private static var article: String {
        "<article><h1>The river plan</h1>" + String(repeating: "<p>\(paragraph)</p>", count: 5) + "</article>"
    }

    private func makePage() -> BrowserPage {
        BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: false
            ),
            delegate: nil
        )
    }

    private func inPage(_ page: BrowserPage, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.extensionWebView.evaluateJavaScript(script, in: nil, in: .page) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    private func waitUntil(_ what: String, _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Never: \(what)")
    }

    /// `pushState`, `replaceState` and a fragment: reader mode closes, and
    /// the address bar asks again about what the page shows then.
    @Test func anAddressChangedWithoutALoadIsAnotherPage() async throws {
        let saved = PageReader.settleDelay
        PageReader.settleDelay = .milliseconds(100)
        defer { PageReader.settleDelay = saved }
        let page = makePage()
        defer { page.teardown() }
        page.extensionWebView.loadHTMLString(
            "<html><body>\(Self.article)</body></html>",
            baseURL: URL(string: "https://example.com/story")
        )
        try await waitUntil("offered") { page.reader.isAvailable }

        page.reader.open(page)
        try await waitUntil("shown") { page.reader.isShown }
        // ⌘+ while it is shown: its text size, not the page's zoom.
        let defaults = try #require(UserDefaults(suiteName: "ReaderPageTests-\(UUID())"))
        let settings = ReaderSettings(defaults: defaults)
        #expect(page.reader.zoom(1, settings: settings) && settings.size > ReaderSettings.defaultSize)
        // Another view of the site: a list, no article.
        _ = await inPage(
            page, "document.body.innerHTML = '<a href=\"/a\">A</a>'; history.pushState({}, '', '/list'); 0"
        )
        try await waitUntil("closed") { !page.reader.isShown }
        #expect(!page.reader.isAvailable)

        // Back to an article: offered again, once the page has shown it.
        let html = Self.article.replacingOccurrences(of: "'", with: "\\'")
        _ = await inPage(page, "history.replaceState({}, '', '/story-2'); document.body.innerHTML = '\(html)'; 0")
        try await waitUntil("offered again") { page.reader.isAvailable }

        page.reader.open(page)
        try await waitUntil("shown again") { page.reader.isShown }
        _ = await inPage(page, "location.hash = 'comments'; 0")
        try await waitUntil("closed by a fragment") { !page.reader.isShown }
    }

    /// ⌘F looks in the article (reader mode's view, JavaScript off for the
    /// page there), not in the page under it.
    @Test func findLooksInTheArticle() async throws {
        let page = makePage()
        defer { page.teardown() }
        let address = try #require(URL(string: "https://example.com/story"))
        let article = try #require(ReaderArticle([
            "title": "Title", "html": "<p>The river and the river banks.</p>", "markdown": "", "words": 6
        ] as [String: Any], pageURL: address))
        let defaults = try #require(UserDefaults(suiteName: "ReaderPageTests-\(UUID())"))
        let style = ReaderSettings(defaults: defaults).style
        let reader = try await ReaderPageView(ReaderDocument.html(for: article, style: style))
        page.reader.webView = reader.webView

        let find = FindController(page: page)
        find.injectMarkJS()
        find.highlight("river")
        var total = 0
        try await waitUntil("found") {
            total = await withCheckedContinuation { continuation in
                find.getMatchInfo { _, total in continuation.resume(returning: total) }
            }
            return total > 0
        }
        #expect(total == 2)
        let marks = try await reader.webView.evaluateJavaScript("document.querySelectorAll('mark').length")
        #expect(marks as? Int == 2)
    }

    /// While the article is shown: ⌘+ and ⌘− its text size, ⌘0 the default;
    /// otherwise the page's zoom.
    @Test func zoomKeysChangeTheTextSize() throws {
        let defaults = try #require(UserDefaults(suiteName: "ReaderPageTests-\(UUID().uuidString)"))
        let settings = ReaderSettings(defaults: defaults)
        let reader = PageReader()
        #expect(!reader.zoom(1, settings: settings))
        #expect(settings.size == ReaderSettings.defaultSize)

        PageReader.changeTextSize(1, settings: settings)
        #expect(settings.size > ReaderSettings.defaultSize)
        PageReader.changeTextSize(-1, settings: settings)
        PageReader.changeTextSize(-1, settings: settings)
        #expect(settings.size < ReaderSettings.defaultSize)
        PageReader.changeTextSize(0, settings: settings)
        #expect(settings.size == ReaderSettings.defaultSize)
    }
}

/// A document in a hidden web view set up as reader mode's.
@MainActor
private final class ReaderPageView: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    init(_ html: String) async throws {
        let configuration = ReaderWebViewCoordinator.configuration(
            dataStore: .nonPersistent(),
            applicationName: nil,
            ruleLists: []
        )
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/story"))
        }
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }
}
