import Foundation
@testable import Ombre
import Testing
import WebKit

/// Page translation: offered for a page in another language than the Mac's,
/// done on the page's text only, undone to the original.
@MainActor
struct PageTranslationTests {
    @Test func languageIsTheTextsWhenSureElseTheDeclaredOne() {
        #expect(PageLanguage.detect(declared: "de-DE", sample: "")?.languageCode == "de")
        let english = "The quick brown fox jumps over the lazy dog while the children are playing in the garden."
        #expect(PageLanguage.detect(declared: "", sample: english)?.languageCode == "en")
        #expect(PageLanguage.detect(declared: "", sample: "") == nil)
        // A template's lang="en" on French text: the text wins.
        let french = "Les enfants jouent dans le jardin pendant que le renard brun saute par-dessus le chien paresseux."
        #expect(PageLanguage.detect(declared: "en", sample: french)?.languageCode == "fr")
        // The same language: the declared region is kept.
        #expect(PageLanguage.detect(declared: "en-GB", sample: english)?.region == "GB")
    }

    /// Not for any of the Mac's languages, like Safari.
    @Test func offeredOnlyForALanguageTheMacDoesntUse() {
        let mac = [Locale.Language(identifier: "fr-FR"), Locale.Language(identifier: "en")]
        #expect(PageLanguage.offersTranslation(of: Locale.Language(identifier: "de"), to: mac))
        #expect(!PageLanguage.offersTranslation(of: Locale.Language(identifier: "fr-CA"), to: mac))
        #expect(!PageLanguage.offersTranslation(of: Locale.Language(identifier: "en-US"), to: mac))
        #expect(!PageLanguage.offersTranslation(of: nil, to: mac))
    }

    private func evaluate(_ page: BrowserPage, _ script: String, world: WKContentWorld = .page) async -> Any? {
        await withCheckedContinuation { continuation in
            page.extensionWebView.evaluateJavaScript(script, in: nil, in: world) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    /// The ring and the panel show the share translated, only while it is.
    @Test func progressIsTheShareTranslatedWhileTranslating() {
        let pair = PageTranslationPair(
            source: Locale.Language(identifier: "de"),
            target: Locale.Language(identifier: "fr")
        )
        #expect(PageTranslationState.translating(pair, done: 0, total: 0).progress == nil)
        #expect(PageTranslationState.translating(pair, done: 1, total: 3).percentDone == 33)
        #expect(PageTranslationState.translating(pair, done: 3, total: 3).percentDone == 100)
        #expect(PageTranslationState.translating(pair, done: 5, total: 3).progress == 1)
        #expect(PageTranslationState.translated(pair).progress == nil)
        #expect(PageTranslationState.preparing(pair).percentDone == nil)
    }

    /// The page's prose is translated, spaces kept; code, fields and what the
    /// page marks as not to translate stay; the original comes back.
    @Test func pageTextIsReplacedAndRestored() async throws {
        let page = BrowserPage(
            profile: BrowserEngineProfile(identifier: UUID(), isPrivate: true),
            configuration: .ombreDefault(
                userScripts: OmbreBrowserScripts.userScripts(),
                privacySettings: SpacePrivacySettings(),
                enablesWebNotifications: false
            ),
            delegate: nil
        )
        defer { page.teardown() }
        page.extensionWebView.loadHTMLString(
            """
            <html lang="en"><body><p id="a"> Hello world </p><code>let x = 1</code>
            <p translate="no" id="b">Brand</p><span class="notranslate">Name</span>
            <p id="c">Good night</p></body></html>
            """,
            baseURL: URL(string: "https://example.com/")
        )
        let app = BrowserPage.appWorld
        for _ in 0 ..< 100 where await evaluate(page, "typeof window.__translator", world: app) as? String != "object" {
            try await Task.sleep(for: .milliseconds(50))
        }

        let info = await evaluate(page, "window.__translator.info()", world: app) as? String
        #expect(info?.contains("\"lang\":\"en\"") == true)
        let collected = await evaluate(page, "window.__translator.collect()", world: app) as? String
        #expect(collected == "[\"Hello world\",\"Good night\"]")

        let info2 = await evaluate(page, "window.__translator.info()", world: app) as? String
        #expect(info2?.contains("\"translated\":false") == true)
        // The page changes a piece meanwhile: it is left alone.
        _ = await evaluate(page, "document.getElementById('c').firstChild.nodeValue = 'Good morning'; true")
        _ = await evaluate(
            page,
            "window.__translator.apply('{\"0\":\"Bonjour le monde\",\"1\":\"Bonne nuit\"}')",
            world: app
        )
        #expect(await evaluate(page, "document.getElementById('a').textContent") as? String == " Bonjour le monde ")
        #expect(await evaluate(page, "document.getElementById('c').textContent") as? String == "Good morning")
        #expect(await (evaluate(page, "window.__translator.info()", world: app) as? String)?
            .contains("\"translated\":true") == true)
        #expect(await evaluate(page, "document.getElementById('b').textContent") as? String == "Brand")

        _ = await evaluate(page, "window.__translator.restore()", world: app)
        #expect(await evaluate(page, "document.getElementById('a').textContent") as? String == " Hello world ")
        // The page itself can't reach it.
        #expect(await evaluate(page, "typeof window.__translator") as? String == "undefined")
    }
}
