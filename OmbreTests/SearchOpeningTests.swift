import Foundation
@testable import Ombre
import Testing

/// Engines that ignore the search in their address: their page opens and
/// the question waits on the clipboard.
@MainActor
struct SearchOpeningTests {
    @Test func anEngineThatTakesTheQuestionGetsItInItsAddress() {
        let opening = SearchOpening.make(
            template: "https://chatgpt.com/?q={query}", acceptsQuery: true, query: "Quelle heure ?"
        )
        #expect(opening?.url.absoluteString == "https://chatgpt.com/?q=Quelle%20heure%20?")
        #expect(opening?.questionToPaste == nil)
    }

    @Test func anEngineThatIgnoresItOpensItsPageWithTheQuestionToPaste() {
        let opening = SearchOpening.make(
            template: "https://gemini.google.com/app?q={query}", acceptsQuery: false, query: "  Quelle heure ?\n"
        )
        #expect(opening?.url.absoluteString == "https://gemini.google.com/app")
        #expect(opening?.questionToPaste == "Quelle heure ?")
    }

    @Test func nothingToPasteWithoutAQuestion() {
        let opening = SearchOpening.make(
            template: "https://gemini.google.com/app?q={query}", acceptsQuery: false, query: "   "
        )
        #expect(opening?.url.absoluteString == "https://gemini.google.com/app")
        #expect(opening?.questionToPaste == nil)
    }

    @Test(arguments: [
        ("https://www.meta.ai/?q={query}", "https://www.meta.ai/"),
        ("https://example.com/search?lang=fr&q={query}", "https://example.com/search?lang=fr"),
        ("https://example.com/search/{query}", "https://example.com/search/"),
        ("https://example.com/ask/{query}/now", "https://example.com/ask/"),
        ("https://example.com/#q={query}", "https://example.com/"),
        ("https://example.com/{query}", "https://example.com/")
    ])
    func thePageKeepsAllButTheSearch(template: String, page: String) {
        #expect(SearchOpening.pageURL(template: template)?.absoluteString == page)
    }

    @Test(arguments: ["javascript:{query}", "file:///tmp/{query}", "https://{query}.example.com/"])
    func neverAnythingButAWebPage(template: String) {
        #expect(SearchOpening.pageURL(template: template) == nil)
    }

    @Test func geminiAndTheUncheckedAIsDoNotTakeTheQuestion() throws {
        let name = "SearchOpeningTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let engines = SearchEngineService(preferences: SearchEnginePreferences(defaults: defaults))
            .builtInSearchEngines
        let ignoring = Set(engines.filter { !$0.acceptsQueryInAddress }.map(\.name))
        #expect(ignoring == ["Gemini", "GitHub Copilot", "Meta AI"])
    }

    @Test func customEnginesSavedBeforeTheSettingTakeTheQuestion() throws {
        let saved = Data("""
        {"id":"1","name":"Mistral","searchURL":"https://chat.mistral.ai/chat?q={query}",\
        "aliases":["mi"],"isAIChat":true}
        """.utf8)
        let engine = try JSONDecoder().decode(CustomSearchEngine.self, from: saved)
        #expect(engine.acceptsQueryInAddress)
    }

    @Test func aCustomEngineKeepsTheSetting() throws {
        let engine = CustomSearchEngine(
            name: "Mine", searchURL: "https://example.com/?q={query}", acceptsQueryInAddress: false
        )
        let decoded = try JSONDecoder().decode(CustomSearchEngine.self, from: JSONEncoder().encode(engine))
        #expect(decoded == engine)
        #expect(!decoded.acceptsQueryInAddress)
    }
}
