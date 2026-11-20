import os.log
import SwiftUI

private let logger = Logger(category: "SearchEngineService")

struct SuggestResponse: Decodable {
    let query: String
    let suggestions: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.query = try container.decode(String.self)
        self.suggestions = try container.decode([String].self)
        // Skip the rest (3rd and 4th elements)
    }
}

/// On the main actor, like the settings it reads (it used to be so only
/// through an `@ObservedObject` wrapper, which did nothing else here).
@MainActor
class SearchEngineService: ObservableObject {
    private var theme: Theme?
    private let settingsStore = SettingsStore.shared
    let preferences: SearchEnginePreferences

    init(preferences: SearchEnginePreferences = .shared) {
        self.preferences = preferences
    }

    func setTheme(_ theme: Theme) {
        self.theme = theme
    }

    var settings: SettingsStore {
        return settingsStore
    }

    var builtInSearchEngines: [SearchEngine] {
        [
            SearchEngine(
                name: "YouTube", // no translation
                color: Color(hex: "#FC0D1B"),
                icon: "",
                aliases: ["youtube", "you", "youtu", "yo", "yt"],
                searchURL: "https://www.youtube.com/results?search_query={query}",
                isAIChat: false
            ),
            SearchEngine(
                name: "ChatGPT", // no translation
                color: theme?.foreground ?? .white,
                icon: "openai-capsule-logo",
                aliases: ["chat", "chatgpt", "gpt", "cgpt", "openai", "cha"],
                searchURL: "https://chatgpt.com/?q={query}",
                isAIChat: true,
                foregroundColor: theme?.background ?? .black
            ),
            SearchEngine(
                name: "Claude", // no translation
                color: Color(hex: "#DE7C4C"),
                icon: "claude-capsule-logo",
                aliases: ["claude", "cl", "cla", "anthropic"],
                searchURL: "https://claude.ai/new?q={query}",
                isAIChat: true
            ),
            SearchEngine(
                name: "Google", // no translation
                color: .blue,
                icon: "google-capsule-logo",
                aliases: ["google", "goo", "g", "search"],
                searchURL:
                "https://www.google.com/search?client=safari&rls=en&ie=UTF-8&oe=UTF-8&q={query}",
                isAIChat: false,
                autoSuggestions: self.googleSuggestions
            ),
            SearchEngine(
                name: "DuckDuckGo", // no translation
                color: Color(hex: "#DE5833"),
                icon: "duckduckgo-capsule-logo",
                aliases: ["duckduckgo", "ddg", "duck"],
                searchURL: "https://duckduckgo.com/?q={query}",
                isAIChat: false
            ),
            SearchEngine(
                name: "Kagi", // no translation
                color: Color(hex: "#FFB319"),
                icon: "kagi-capsule-logo",
                aliases: ["kagi", "kg"],
                searchURL: "https://kagi.com/search?q={query}",
                isAIChat: false
            ),
            SearchEngine(
                name: "Bing", // no translation
                color: Color(hex: "#02B7E9"),
                icon: "bing-capsule-logo",
                aliases: ["bing", "b", "microsoft"],
                searchURL: "https://www.bing.com/search?q={query}",
                isAIChat: false
            ),
            SearchEngine(
                name: "Grok", // no translation
                color: theme?.foreground ?? .white,
                icon: "grok-capsule-logo",
                aliases: ["grok", "gr", "gro"],
                searchURL: "https://grok.com/?q={query}",
                isAIChat: true,
                foregroundColor: theme?.background ?? .black
            ),
            SearchEngine(
                name: "Perplexity", // no translation
                color: Color(hex: "#20808D"),
                icon: "perplexity-capsule-logo",
                aliases: ["perplexity", "perplex", "pplx", "ppl", "per"],
                searchURL: "https://www.perplexity.ai/search/new?q={query}",
                isAIChat: true
            ),
            SearchEngine(
                name: "Reddit", // no translation
                color: Color(hex: "#FF4500"),
                icon: "reddit-capsule-logo",
                aliases: ["reddit", "r", "rd", "rdit", "red"],
                searchURL: "https://www.reddit.com/search/?q={query}",
                isAIChat: false
            ),
            SearchEngine(
                name: "T3Chat", // no translation
                color: Color(hex: "#960971"),
                icon: "t3chat-capsule-logo",
                aliases: ["t3chat", "t3", "t3c", "tchat"],
                searchURL: "https://t3.chat/new?q={query}",
                isAIChat: true
            ),
            SearchEngine(
                name: "X", // no translation
                color: theme?.foreground ?? .white,
                icon: "x-capsule-logo",
                aliases: ["x", "x.com", "twitter", "tw", "twtr", "twit", "twitt", "twitte"],
                searchURL: "https://x.com/search?q={query}",
                isAIChat: false,
                foregroundColor: theme?.background ?? .black
            ),
            SearchEngine(
                name: "Gemini", // no translation
                color: Color(hex: "#4285F4"),
                icon: "gemini-color-capsule-logo",
                aliases: ["gemini", "gem", "bard", "google ai", "gai"], // no translation
                searchURL: "https://gemini.google.com/app?q={query}",
                isAIChat: true,
                acceptsQueryInAddress: false
            ),
            SearchEngine(
                name: "Copilot", // no translation
                color: Color(hex: "#0078D4"),
                icon: "copilot-color-capsule-logo",
                aliases: ["copilot", "microsoft copilot", "bing chat", "ms copilot"], // no translation
                searchURL: "https://copilot.microsoft.com/?q={query}",
                isAIChat: true
            ),
            SearchEngine(
                name: "GitHub Copilot", // no translation
                color: Color(hex: "#24292F"),
                icon: "copilot-color-capsule-logo",
                aliases: ["github copilot", "gh copilot", "github ai", "ghc"], // no translation
                searchURL: "https://github.com/copilot?q={query}",
                isAIChat: true,
                acceptsQueryInAddress: false,
                foregroundColor: .white
            ),
            SearchEngine(
                name: "Meta AI", // no translation
                color: Color(hex: "#0866FF"),
                icon: "",
                aliases: ["meta ai", "meta", "llama", "facebook ai", "mai"], // no translation
                searchURL: "https://www.meta.ai/?q={query}",
                isAIChat: true,
                acceptsQueryInAddress: false
            )
        ]
    }

    /// Every engine, built-in (with the keywords chosen for it) then custom.
    var searchEngines: [SearchEngine] {
        var engines = builtInSearchEngines.map { engine in
            engine.with(aliases: preferences.keywords(of: engine.name, own: engine.aliases))
        }

        let customEngines = settingsStore.customSearchEngines.map { custom in
            SearchEngine(
                name: custom.name,
                color: custom.faviconBackgroundColor ?? .blue,
                icon: "",
                aliases: custom.aliases,
                searchURL: custom.searchURL,
                isAIChat: custom.isAIChat,
                acceptsQueryInAddress: custom.acceptsQueryInAddress
            )
        }

        engines.append(contentsOf: customEngines)
        return engines
    }

    /// What decides which engines show and which AI a space asks.
    var rules: SearchEngineRules {
        SearchEngineRules(
            engines: searchEngines,
            isChosenShown: { [preferences] in preferences.isChosenShown($0) },
            globalSearch: settingsStore.globalDefaultSearchEngine,
            globalAI: preferences.globalAI,
            spaceChoices: settingsStore.spaceEngineChoices
        )
    }

    /// The shown engine a keyword opens: a hidden one's keywords do nothing.
    func findSearchEngine(for alias: String) -> SearchEngine? {
        rules.engine(forKeyword: alias)
    }

    /// The engines offered: built-in and custom, hidden ones left out.
    var shownEngines: [SearchEngine] {
        let rules = rules
        return rules.engines.filter { rules.isShown($0.name) }
    }

    /// Chooses the engine (`isAI` false) or AI for a space; nil: the choice
    /// for all spaces. A chosen engine shows (it cannot be hidden).
    func choose(_ name: String?, isAI: Bool, for containerId: UUID) {
        if isAI {
            settingsStore.setDefaultAIEngineId(name, for: containerId)
        } else {
            settingsStore.setDefaultSearchEngineId(name, for: containerId)
        }
    }

    func getDefaultSearchEngine(for containerId: UUID? = nil) -> SearchEngine? {
        // First check per-container setting
        if let containerId,
           let defaultId = settingsStore.defaultSearchEngineId(for: containerId),
           let engine = searchEngines.first(where: { $0.name == defaultId })
        {
            return engine
        }

        // Then check global default setting
        if let globalDefaultId = settingsStore.globalDefaultSearchEngine,
           let engine = searchEngines.first(where: { $0.name == globalDefaultId })
        {
            return engine
        }

        // Fallback to Google if no custom default is set
        return searchEngines.first(where: { $0.name == "Google" }) // no translation
    }

    /// Where a search typed in a space goes: its engine, else the engine for
    /// all spaces. Nil when neither makes an address: nothing is sent (never
    /// to another engine than the one chosen).
    func searchURL(for query: String, containerId: UUID?) -> URL? {
        let chosenIDs = [
            containerId.flatMap(settingsStore.defaultSearchEngineId(for:)),
            settingsStore.globalDefaultSearchEngine
        ].compactMap(\.self)
        // Ombre's default (Google) only when no engine is chosen at all; a
        // chosen engine since removed is still a choice: not replaced.
        let engines = chosenIDs.isEmpty
            ? [getDefaultSearchEngine(for: nil)]
            : chosenIDs.map { id in searchEngines.first { $0.name == id } }
        return Self.firstSearchURL(for: query, engines: engines)
    }

    nonisolated static func firstSearchURL(for query: String, engines: [SearchEngine?]) -> URL? {
        engines.lazy.compactMap { $0.flatMap { searchURL(template: $0.searchURL, query: query) } }.first
    }

    /// `query` in an engine's template; nil unless it makes a web address
    /// (never a `file:` or `javascript:` one, even through an alias).
    nonisolated static func searchURL(template: String, query: String) -> URL? {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return webURL(template.replacingOccurrences(of: "{query}", with: encodedQuery))
    }

    /// A template the settings accept: one Ombre will search with
    /// (`{query}`, then a web address with a host).
    nonisolated static func isValidTemplate(_ template: String) -> Bool {
        template.contains("{query}") && webURL(template.replacingOccurrences(of: "{query}", with: "test")) != nil
    }

    /// `address` as an http(s) address with a host; nil otherwise.
    private nonisolated static func webURL(_ address: String) -> URL? {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// The AI a space asks: its own, else the one for all spaces, else ChatGPT.
    func getDefaultAIChat(for containerId: UUID? = nil) -> SearchEngine? {
        rules.aiEngine(spaceChoice: containerId.flatMap(settingsStore.defaultAIEngineId(for:)))
    }

    func getSearchEngine(byName name: String) -> SearchEngine? {
        return searchEngines.first(where: { $0.name == name })
    }

    /// The address to open for `query`, to be opened at once. When the
    /// engine ignores the search in its address: its page, and (a side
    /// effect) the question put on the clipboard, with a message saying so.
    /// Private: the copy is marked for clipboard managers not to keep it.
    func urlToOpen(
        for engine: SearchEngine, query: String, isPrivate: Bool, toasts: ToastManager = .shared
    ) -> URL? {
        urlToOpen(
            SearchOpening.make(template: engine.searchURL, acceptsQuery: engine.acceptsQueryInAddress, query: query),
            isPrivate: isPrivate,
            toasts: toasts
        )
    }

    func urlToOpen(
        for match: LauncherMatch, query: String, isPrivate: Bool, toasts: ToastManager = .shared
    ) -> URL? {
        urlToOpen(
            SearchOpening.make(template: match.searchURL, acceptsQuery: match.acceptsQueryInAddress, query: query),
            isPrivate: isPrivate,
            toasts: toasts
        )
    }

    private func urlToOpen(_ opening: SearchOpening?, isPrivate: Bool, toasts: ToastManager) -> URL? {
        guard let opening else { return nil }
        if let question = opening.questionToPaste {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(question, forType: .string)
            if isPrivate {
                // The nspasteboard.org markers clipboard histories respect.
                for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
                    pasteboard.setString("", forType: NSPasteboard.PasteboardType(marker))
                }
            }
            toasts.show(String(localized: "Question copied: paste it with ⌘V"), icon: .ombre(.copy))
        }
        return opening.url
    }

    func createSuggestionsURL(urlString: String, query: String) -> URL? {
        let encodedQuery =
            query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = urlString.replacingOccurrences(of: "{query}", with: encodedQuery)
        return URL(string: urlString)
    }

    func googleSuggestions(_ query: String) async -> [String] {
        guard
            let url = createSuggestionsURL(
                urlString:
                "https://suggestqueries.google.com/complete/search?client=firefox&q={query}",
                query: query
            )
        else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(SuggestResponse.self, from: data)
            return decoded.suggestions
        } catch {
            logger.error("Error fetching Google suggestions: \(error.localizedDescription)")
            return []
        }
    }
}
