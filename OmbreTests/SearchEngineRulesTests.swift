import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// Engines shown or hidden, their keywords, and each space's AI.
@MainActor
struct SearchEngineRulesTests {
    private func engine(_ name: String, _ aliases: [String], isAI: Bool = false) -> SearchEngine {
        SearchEngine(
            name: name,
            color: .gray,
            icon: "",
            aliases: aliases,
            searchURL: "https://example.com/\(name)?q={query}",
            isAIChat: isAI
        )
    }

    private var engines: [SearchEngine] {
        [
            engine("Google", ["g", "google"]),
            engine("YouTube", ["yt"]),
            engine("X", ["x", "tw"]),
            engine("ChatGPT", ["gpt"], isAI: true),
            engine("Claude", ["cl"], isAI: true),
            engine("Grok", ["gr"], isAI: true),
            engine("Mine", ["mi"], isAI: true)
        ]
    }

    private func rules(
        hidden: Set<String> = SearchEnginePreferences.hiddenByDefault,
        globalSearch: String? = nil,
        globalAI: String? = nil
    ) -> SearchEngineRules {
        SearchEngineRules(
            engines: engines,
            isChosenShown: { !hidden.contains($0) },
            globalSearch: globalSearch,
            globalAI: globalAI
        )
    }

    private func preferences() throws -> SearchEnginePreferences {
        let name = "SearchEngineRulesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return SearchEnginePreferences(defaults: defaults)
    }

    // MARK: - Shown and hidden

    @Test func theListedEnginesAreHiddenAtFirst() throws {
        let preferences = try preferences()
        for name in ["X", "Grok", "T3Chat", "Copilot", "GitHub Copilot", "Meta AI"] {
            #expect(!preferences.isChosenShown(name), "\(name)")
        }
        for name in [
            "Google",
            "DuckDuckGo",
            "Kagi",
            "Bing",
            "YouTube",
            "Reddit",
            "ChatGPT",
            "Claude",
            "Perplexity",
            "Gemini",
            "A custom engine"
        ] {
            #expect(preferences.isChosenShown(name), "\(name)")
        }
    }

    @Test func aChoiceToShowOrHideIsKept() throws {
        let preferences = try preferences()
        preferences.setShown(true, "Grok")
        preferences.setShown(false, "YouTube")
        #expect(preferences.isChosenShown("Grok"))
        #expect(!preferences.isChosenShown("YouTube"))
    }

    @Test func aHiddenEnginesKeywordsDoNothing() {
        let rules = rules()
        #expect(rules.engine(forKeyword: "yt")?.name == "YouTube")
        #expect(rules.engine(forKeyword: "tw") == nil)
        #expect(rules.engine(forKeyword: "gr") == nil)
        #expect(rules.engine(forKeyword: "nothing") == nil)
    }

    @Test func keywordsAreFoundWhateverTheirCase() {
        #expect(rules().engine(forKeyword: "CL")?.name == "Claude")
    }

    /// The default engine and AI cannot be hidden: their keywords still work.
    @Test func theDefaultsAlwaysShow() {
        let rules = rules(hidden: ["X", "Google", "ChatGPT", "Grok"], globalAI: "Grok")
        #expect(rules.isShown("Google"))
        #expect(rules.isShown("Grok"))
        #expect(rules.engine(forKeyword: "gr")?.name == "Grok")
        // ChatGPT is no longer the default AI: hidden as chosen.
        #expect(!rules.isShown("ChatGPT"))
        #expect(!rules.isShown("X"))
    }

    /// A space's choice made before engines could be hidden still shows.
    @Test func aSpacesChoiceAlwaysShows() {
        var rules = rules()
        #expect(rules.engine(forKeyword: "tw") == nil)
        rules.spaceChoices = ["X"]
        #expect(rules.isLocked("X"))
        #expect(rules.engine(forKeyword: "tw")?.name == "X")
    }

    // MARK: - The space's AI

    @Test func aSpaceAsksItsOwnAI() {
        #expect(rules(globalAI: "Grok").aiEngine(spaceChoice: "Claude")?.name == "Claude")
    }

    @Test func aSpaceWithoutAChoiceAsksTheGlobalAI() {
        #expect(rules(globalAI: "Claude").aiEngine(spaceChoice: nil)?.name == "Claude")
    }

    @Test func withoutAnyChoiceItIsChatGPT() {
        #expect(rules().aiEngine(spaceChoice: nil)?.name == "ChatGPT")
    }

    @Test func aCustomAIEngineCanBeASpacesAI() {
        #expect(rules().aiEngine(spaceChoice: "Mine")?.name == "Mine")
    }

    /// A choice since removed, or that is not an AI, falls back.
    @Test func aChoiceGoneOrNotAnAIFallsBack() {
        #expect(rules(globalAI: "Claude").aiEngine(spaceChoice: "Removed")?.name == "Claude")
        #expect(rules(globalAI: "YouTube").aiEngine(spaceChoice: "Google")?.name == "ChatGPT")
    }

    /// Through the service, with a space's choice kept in the settings.
    @Test func theServiceAsksTheSpacesAIThenTheGlobalOne() throws {
        let preferences = try preferences()
        preferences.globalAI = "Claude"
        let service = SearchEngineService(preferences: preferences)
        let space = UUID()
        defer { SettingsStore.shared.removeContainerSettings(for: space) }

        #expect(service.getDefaultAIChat(for: space)?.name == "Claude")
        service.choose("Grok", isAI: true, for: space)
        #expect(service.getDefaultAIChat(for: space)?.name == "Grok")
        // Chosen by a space: shown, with its keywords, though hidden at first.
        #expect(!preferences.isChosenShown("Grok"))
        #expect(service.rules.isLocked("Grok"))
        #expect(service.findSearchEngine(for: "grok")?.name == "Grok")
        service.choose(nil, isAI: true, for: space)
        #expect(service.getDefaultAIChat(for: space)?.name == "Claude")
    }

    @Test func theServiceIgnoresAHiddenEnginesKeywords() throws {
        let preferences = try preferences()
        let service = SearchEngineService(preferences: preferences)
        #expect(service.findSearchEngine(for: "yt")?.name == "YouTube")
        preferences.setShown(false, "YouTube")
        #expect(service.findSearchEngine(for: "yt") == nil)
        #expect(!service.shownEngines.contains { $0.name == "YouTube" })
        // Its keywords changed: the new ones work, the old ones no longer.
        preferences.setShown(true, "YouTube")
        preferences.setKeywords(["video"], for: "YouTube")
        #expect(service.findSearchEngine(for: "video")?.name == "YouTube")
        #expect(service.findSearchEngine(for: "yt") == nil)
    }

    // MARK: - Keywords

    @Test func keywordsAreReadAsTyped() {
        #expect(SearchEngineRules.keywords(from: "YT, you tube,yt , ") == ["yt", "you tube"])
        // Only commas separate: a keyword may have spaces.
        #expect(SearchEngineRules.keywords(from: "microsoft copilot") == ["microsoft copilot"])
        #expect(SearchEngineRules.keywords(from: "  ").isEmpty)
    }

    @Test func aKeywordOfAnotherShownEngineIsAConflict() {
        let rules = rules()
        #expect(rules.conflicts(of: ["yt", "new"], for: "Claude") == ["yt": "YouTube"])
        // Its own keywords are not; a hidden engine's are (shown again, it
        // would take them back).
        #expect(rules.conflicts(of: ["cl"], for: "Claude").isEmpty)
        #expect(rules.conflicts(of: ["tw"], for: "Claude") == ["tw": "X"])
    }

    @Test func chosenKeywordsReplaceTheEnginesOwn() throws {
        let preferences = try preferences()
        #expect(preferences.keywords(of: "YouTube", own: ["yt"]) == ["yt"])
        preferences.setKeywords(["video"], for: "YouTube")
        #expect(preferences.keywords(of: "YouTube", own: ["yt"]) == ["video"])
        preferences.setKeywords(nil, for: "YouTube")
        #expect(preferences.keywords(of: "YouTube", own: ["yt"]) == ["yt"])
    }

    @Test func aRenamedEngineKeepsItsChoices() throws {
        let preferences = try preferences()
        preferences.setShown(false, "Mine")
        preferences.globalAI = "Mine"
        preferences.rename("Mine", to: "Ours")
        #expect(!preferences.isChosenShown("Ours"))
        #expect(preferences.globalAI == "Ours")
        preferences.rename("Ours", to: nil)
        #expect(preferences.isChosenShown("Ours"))
        #expect(preferences.globalAI == nil)
    }

    // MARK: - Keywords begun

    @Test func theStartOfAKeywordOffersItsEngine() {
        let rules = rules()
        #expect(rules.keywordMatches(for: "yt").map(\.engine.name) == ["YouTube"])
        #expect(rules.keywordMatches(for: "goo").map(\.engine.name) == ["Google"])
        #expect(rules.keywordMatches(for: "GOO").first?.keyword == "google")
        #expect(rules.keywordMatches(for: "nothing").isEmpty)
        #expect(rules.keywordMatches(for: "  ").isEmpty)
    }

    /// One letter offers nothing, unless it is a keyword.
    @Test func oneLetterOffersOnlyAnExactKeyword() {
        let rules = rules()
        #expect(rules.keywordMatches(for: "g").map(\.engine.name) == ["Google"])
        #expect(rules.keywordMatches(for: "y").isEmpty)
    }

    /// A hidden engine is never offered.
    @Test func aHiddenEngineIsNotOffered() {
        #expect(rules().keywordMatches(for: "gr").isEmpty)
        #expect(rules().keywordMatches(for: "tw").isEmpty)
    }

    /// An exact keyword first, then the shortest, two at most.
    @Test func theBestTwoComeFirst() {
        let rules = SearchEngineRules(
            engines: [
                engine("Long", ["chatbot"]),
                engine("Short", ["chat"]),
                engine("Exact", ["ch", "chx"]),
                engine("Other", ["cha"])
            ],
            isChosenShown: { _ in true },
            globalSearch: "Long",
            globalAI: nil
        )
        #expect(rules.keywordMatches(for: "ch").map(\.engine.name) == ["Exact", "Other"])
        #expect(rules.keywordMatches(for: "cha").map(\.engine.name) == ["Other", "Short"])
        #expect(rules.keywordMatches(for: "chat", limit: 3).map(\.engine.name) == ["Short", "Long"])
        #expect(rules.keywordMatches(for: "ch").first?.isExact == true)
        #expect(rules.keywordMatches(for: "cha").last?.isExact == false)
    }

    // MARK: - Built-in engines

    @Test func everyBuiltInEngineMakesAWebAddress() {
        for engine in SearchEngineService().builtInSearchEngines {
            #expect(SearchEngineService.isValidTemplate(engine.searchURL), "\(engine.name)")
        }
    }

    /// The names hidden by default are real engines (a typo would leave one shown).
    @Test func theEnginesHiddenByDefaultExist() {
        let names = Set(SearchEngineService().builtInSearchEngines.map(\.name))
        #expect(SearchEnginePreferences.hiddenByDefault.isSubset(of: names))
        #expect(names.contains(SearchEnginePreferences.fallbackAI))
        #expect(names.contains(SearchEngineRules.fallbackSearch))
    }

    /// Claude asks the question in a new chat (claude.ai alone drops it).
    @Test func claudeAsksInANewChat() throws {
        let claude = try #require(SearchEngineService().builtInSearchEngines.first { $0.name == "Claude" })
        #expect(SearchEngineService.searchURL(template: claude.searchURL, query: "a b")?.absoluteString
            == "https://claude.ai/new?q=a%20b")
    }

    // MARK: - Custom engine addresses

    @Test func percentSStandsForTheSearch() {
        #expect(SearchEngineRules.template(from: " https://a.example/s?q=%s ") == "https://a.example/s?q={query}")
        #expect(SearchEngineService.isValidTemplate(SearchEngineRules.template(from: "https://a.example/?q=%s")))
        #expect(!SearchEngineService.isValidTemplate(SearchEngineRules.template(from: "https://a.example/")))
    }

    // MARK: - Questions in the address bar

    @Test func questionsInFrenchOrEnglishAreOfferedToTheAI() {
        #expect(LauncherViewModel.isAISuitableQuery("comment faire une tarte"))
        #expect(LauncherViewModel.isAISuitableQuery("pourquoi le ciel est bleu"))
        #expect(LauncherViewModel.isAISuitableQuery("how do magnets work"))
        #expect(LauncherViewModel.isAISuitableQuery("résume cet article"))
        #expect(!LauncherViewModel.isAISuitableQuery("météo"))
        #expect(!LauncherViewModel.isAISuitableQuery("example.com"))
    }
}
