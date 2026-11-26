import AppKit
import Foundation
@testable import Ombre
import Testing
import WebKit

/// Reader mode: the article taken from real pages in a hidden web view
/// (never in a window), the reader's document, its note and its settings.
@MainActor
struct ReaderTests {
    private static let pageURL = URL(string: "https://news.example.com/2026/story")!

    private static let paragraph = """
    The council met on Tuesday evening to discuss the new plan for the river banks, which has been debated \
    for months, and residents came in numbers to hear what would change for them, their streets and their homes.
    """

    /// A news page: navigation, share buttons, a sidebar, comments and the article.
    private static let newsPage = """
    <header class="site-header"><nav class="main-nav"><a href="/">Home</a> <a href="/world">World</a></nav></header>
    <div class="layout">
      <article class="post">
        <h1>The river plan is approved</h1>
        <p class="byline">By Jane Doe</p>
        <div class="share-buttons"><a href="https://social.example/share">Share</a> <a href="#">Tweet</a></div>
        <div class="article-body">
          <p>\(paragraph)</p>
          <p style="color: red" onclick="alert(1)">\(paragraph) <a href="/plan.pdf">Read the plan</a>.</p>
          <h2>What changes</h2>
          <figure><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" data-src="/images/river.jpg" alt="The river">
            <figcaption>The river at dawn</figcaption></figure>
          <script>document.title = "ran";</script>
          <iframe src="https://ads.example/frame"></iframe>
          <ul><li>Wider paths</li><li>New trees</li></ul>
          <p>\(paragraph)</p>
          <pre>let a = 1
    let b = 2</pre>
          <p>\(paragraph)</p>
        </div>
      </article>
      <aside class="sidebar"><h3>Most read</h3><a href="/a">Other story</a></aside>
      <section class="comments">
        <p>First comment that is quite long but still a comment and not the article.</p>
      </section>
    </div>
    <footer class="site-footer">© News</footer>
    """

    private func extract(_ body: String, head: String = "") async throws -> ReaderArticle? {
        let page = try await OffscreenPage(head + body, baseURL: Self.pageURL)
        let value = try await page.run(script: ReaderScript.script("return reader.extract();"), in: ReaderScript.world)
        return ReaderArticle(value, pageURL: Self.pageURL)
    }

    private func isReadable(_ body: String) async throws -> Bool {
        let page = try await OffscreenPage(body, baseURL: Self.pageURL)
        let script = ReaderScript.script("return reader.isReadable();")
        let value = try await page.run(script: script, in: ReaderScript.world)
        return value as? Bool ?? false
    }

    @Test func theArticleWithoutWhatSurroundsIt() async throws {
        let article = try #require(try await extract(Self.newsPage))
        #expect(article.title == "The river plan is approved")
        #expect(article.byline == "By Jane Doe")
        #expect(article.site == "news.example.com")
        #expect(article.html.contains("The council met on Tuesday"))
        #expect(article.html.contains("What changes"))
        for left in ["Home", "Most read", "First comment", "© News", "Tweet"] {
            #expect(!article.html.contains(left), "\(left) is not the article")
        }
        // The title is shown by the reader once, not twice.
        #expect(!article.html.contains("<h1"))
    }

    @Test func nothingOfItCanRunOrKeepThePageLook() async throws {
        let article = try #require(try await extract(Self.newsPage))
        for forbidden in ["<script", "onclick", "style=", "<iframe", "class=", "ads.example", "document.title"] {
            #expect(!article.html.contains(forbidden), "\(forbidden) kept")
        }
    }

    /// Addresses made absolute; an image loaded late by the page, from its real address.
    @Test func imagesAndLinksAtTheirFullAddress() async throws {
        let article = try #require(try await extract(Self.newsPage))
        #expect(article.images == ["https://news.example.com/images/river.jpg"])
        #expect(article.html.contains(#"href="https://news.example.com/plan.pdf""#))
        #expect(article.html.contains(#"alt="The river""#))
        #expect(article.html.contains("<figcaption>The river at dawn</figcaption>"))
    }

    @Test func markdownForANote() async throws {
        let article = try #require(try await extract(Self.newsPage))
        #expect(article.markdown.contains("## What changes"))
        #expect(article.markdown.contains("![The river](https://news.example.com/images/river.jpg)"))
        #expect(article.markdown.contains("[Read the plan](https://news.example.com/plan.pdf)"))
        #expect(article.markdown.contains("- Wider paths\n- New trees"))
        #expect(article.markdown.contains("```\nlet a = 1\nlet b = 2\n```"))
        #expect(article.words > 100)
        #expect(article.minutes == 1)
    }

    @Test func titleAndDateFromThePageDescription() async throws {
        let head = """
        <meta property="og:site_name" content="Example News">
        <meta property="article:published_time" content="2026-03-12T08:30:00Z">
        <meta name="author" content="John Roe">
        """
        let paragraphs = String(repeating: "<p>\(Self.paragraph)</p>", count: 4)
        let body = "<main><div class=\"text\">" + paragraphs + "</div></main>"
        let article = try #require(try await extract(body, head: head))
        #expect(article.site == "Example News")
        #expect(article.byline == "John Roe")
        let date = try #require(article.published)
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(Calendar(identifier: .gregorian).dateComponents(in: utc, from: date).day == 12)
    }

    /// Like Safari's button: an article, not a list of links or a short page.
    @Test func offeredForArticlesOnly() async throws {
        #expect(try await isReadable(Self.newsPage))
        #expect(try await isReadable("<p>Hello.</p><p>A short page.</p>") == false)
        let links = (1 ... 40).map { "<li><a href=\"/\($0)\">Story number \($0) of the day</a></li>" }.joined()
        #expect(try await isReadable("<nav><ul>\(links)</ul></nav>") == false)
        #expect(try await extract("<p>Hello.</p>") == nil)
    }

    // MARK: - The reader's document

    @Test func theDocumentEscapesWhatThePageSays() throws {
        let article = try #require(ReaderArticle([
            "title": "<b>Bold</b> & \"quoted\"", "byline": "<i>me</i>", "site": "x<y", "html": "<p>Text</p>",
            "markdown": "Text", "images": [String](), "words": 460
        ] as [String: Any], pageURL: Self.pageURL))
        let html = ReaderDocument.html(for: article, style: ReaderSettings(defaults: makeDefaults()).style)
        #expect(html.contains("&lt;b&gt;Bold&lt;/b&gt; &amp; &quot;quoted&quot;"))
        #expect(html.contains("&lt;i&gt;me&lt;/i&gt;"))
        #expect(html.contains(ReaderDocument.contentSecurityPolicy))
        #expect(html.contains("data-theme=\"automatic\""))
        #expect(article.minutes == 2)
    }

    /// Shown with JavaScript off: even a script left in the article never
    /// runs; the app's own script still changes the style.
    @Test func noScriptRunsButTheStyleChanges() async throws {
        let article = try #require(ReaderArticle([
            "title": "Title", "site": "example.com", "words": 10, "images": [String](), "markdown": "",
            "html": "<p>Text</p><script>document.title = 'ran'</script><img src=x onerror=\"document.title='ran'\">"
        ] as [String: Any], pageURL: Self.pageURL))
        let settings = ReaderSettings(defaults: makeDefaults())
        let reader = try await ReaderDocumentView(ReaderDocument.html(for: article, style: settings.style))
        #expect(try await reader.evaluate("document.title") as? String == "Title")
        settings.theme = .sepia
        settings.makeTextBigger()
        _ = try await reader.evaluate(ReaderDocument.applyScript(for: settings.style) + "; 0")
        #expect(try await reader.evaluate("document.documentElement.dataset.theme") as? String == "sepia")
        #expect(try await reader.evaluate("getComputedStyle(document.body).fontSize") as? String == "22px")
        #expect(try await reader.evaluate("document.title") as? String == "Title")
    }

    // MARK: - Note and settings

    @Test func theNoteUsesTheSavedImages() throws {
        let article = try #require(ReaderArticle([
            "title": "A [story]", "site": "example.com", "words": 300, "html": "<p>x</p>",
            "markdown": "Text\n\n![A](https://example.com/a%20b.jpg)\n\n![B](https://example.com/b.png)\n\n"
                + "![](https://example.com/c.png)\n\n![D](data:image/png;base64,AAAA)",
            "images": [
                "https://example.com/a b.jpg",
                "https://example.com/b.png",
                "https://example.com/c.png",
                "data:image/png;base64,AAAA"
            ],
            "byline": "*Jane* _Doe_"
        ] as [String: Any], pageURL: Self.pageURL))
        let text = ReaderNote.markdown(
            for: article,
            images: ["https://example.com/a b.jpg": "attachments/article-1.jpg"]
        )
        // The page's words never become Markdown marks.
        #expect(text.hasPrefix(#"[A \[story\]](https://news.example.com/2026/story)"# + "\n\n*\\*Jane\\* \\_Doe\\_"))
        #expect(text.contains("![A](attachments/article-1.jpg)"))
        // Not saved: a link to the site's image (a note shows only its own
        // files); an embedded one, nothing.
        #expect(text.contains("[B](https://example.com/b.png)") && !text.contains("![B]"))
        #expect(text
            .contains("[\(String(localized: "reader.note.image", defaultValue: "Image"))](https://example.com/c.png)"))
        #expect(!text.contains("data:"))
        #expect(ReaderNote.fileExtension(for: "image/jpeg", suggested: nil) == "jpg")
        #expect(ReaderNote.fileExtension(for: "text/html", suggested: "page.html") == nil)
        #expect(ReaderNote.fileExtension(for: nil, suggested: "photo.WEBP") == "webp")
    }

    @Test func settingsAreKept() {
        let defaults = makeDefaults()
        let settings = ReaderSettings(defaults: defaults)
        #expect(settings.theme == .automatic && settings.size == ReaderSettings.defaultSize)
        settings.theme = .dark
        settings.width = .wide
        settings.font = .serif
        for _ in 0 ..< 20 {
            settings.makeTextBigger()
        }
        #expect(settings.size == ReaderSettings.sizes.last)
        #expect(!settings.canMakeTextBigger)
        let again = ReaderSettings(defaults: defaults)
        #expect(again.theme == .dark && again.width == .wide && again.font == .serif && again.size == 32)
        again.resetTextSize()
        #expect(again.size == ReaderSettings.defaultSize)
    }

    /// As Safari: ⇧⌘R reader, ⌥⌘R cache, ⌥⇧⌘R cookies.
    @Test func safariShortcuts() {
        #expect(KeyboardShortcuts.Page.reader.defaultChord == KeyChord(
            keyEquivalent: .init("r"), modifiers: [.command, .shift]
        ))
        #expect(KeyboardShortcuts.Navigation.hardReload.defaultChord == KeyChord(
            keyEquivalent: .init("r"), modifiers: [.command, .option]
        ))
        #expect(KeyboardShortcuts.Navigation.clearCookiesAndReload.defaultChord == KeyChord(
            keyEquivalent: .init("r"), modifiers: [.command, .option, .shift]
        ))
        #expect(KeyboardShortcuts.allShortcuts.contains { $0.id == KeyboardShortcuts.Page.reader.id })
    }

    /// The reader shows its article only: links open in the page.
    @Test func linksOpenInThePage() throws {
        let page = Self.pageURL
        let decide = { (url: String, type: WKNavigationType, main: Bool) in
            ReaderWebViewCoordinator.decision(for: URL(string: url), type: type, isMainFrame: main, pageURL: page)
        }
        // The article itself, loaded by the app.
        #expect(decide(page.absoluteString, .other, true) == .allow)
        // A part of the article: there, in the reader.
        #expect(decide(page.absoluteString + "#notes", .linkActivated, true) == .allow)
        let other = try #require(URL(string: "https://example.org/next"))
        #expect(decide(other.absoluteString, .linkActivated, true) == .open(other))
        // Nothing else loads: a redirect, a form, a frame.
        #expect(decide(other.absoluteString, .other, true) == .cancel)
        #expect(decide(other.absoluteString, .formSubmitted, true) == .cancel)
        #expect(decide(other.absoluteString, .linkActivated, false) == .cancel)
    }

    @Test func onlyWebPages() {
        #expect(PageReader.canRead(URL(string: "https://example.com")))
        #expect(!PageReader.canRead(URL(string: "file:///tmp/a.html")))
        #expect(!PageReader.canRead(nil))
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ReaderTests-\(UUID().uuidString)") ?? .standard
    }
}

/// The reader's document in a hidden web view set up as reader mode's.
@MainActor
private final class ReaderDocumentView: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    init(_ html: String) async throws {
        // Reader mode's own settings, as its web view gets them.
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
            webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
        }
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }
}
