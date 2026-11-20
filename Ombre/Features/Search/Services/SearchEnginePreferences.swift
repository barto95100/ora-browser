import Combine
import Foundation

/// What the Search settings choose beyond the engines themselves: which
/// engines show, the keywords of the built-in ones, and the AI for all
/// spaces. Shown engines are offered in the address bar and their keywords
/// work; a hidden one is neither.
@MainActor
final class SearchEnginePreferences: ObservableObject {
    static let shared = SearchEnginePreferences()

    /// Shown unless chosen otherwise: the others are hidden at first.
    nonisolated static let hiddenByDefault: Set<String> = [
        "X", "Grok", "T3Chat", "Copilot", "GitHub Copilot", "Meta AI" // no translation
    ]
    /// The AI for spaces that choose none, until one is chosen here.
    nonisolated static let fallbackAI = "ChatGPT" // no translation

    private let defaults: UserDefaults
    private let visibilityKey = "settings.search.visibility"
    private let keywordsKey = "settings.search.keywords"
    private let globalAIKey = "settings.search.globalAI"

    /// Shown (true) or hidden (false) as chosen; absent: as by default.
    @Published private(set) var visibility: [String: Bool]
    /// The keywords chosen for a built-in engine, in place of its own.
    @Published private(set) var keywords: [String: [String]]
    /// The AI chosen for all spaces; nil: `fallbackAI`.
    @Published var globalAI: String? {
        didSet { defaults.set(globalAI, forKey: globalAIKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visibility = defaults.dictionary(forKey: visibilityKey) as? [String: Bool] ?? [:]
        keywords = defaults.dictionary(forKey: keywordsKey) as? [String: [String]] ?? [:]
        globalAI = defaults.string(forKey: globalAIKey)
    }

    /// Shown as chosen, else as by default.
    func isChosenShown(_ name: String) -> Bool {
        visibility[name] ?? !Self.hiddenByDefault.contains(name)
    }

    func setShown(_ shown: Bool, _ name: String) {
        visibility[name] = shown
        defaults.set(visibility, forKey: visibilityKey)
    }

    /// The keywords of `name`: chosen, else its own.
    func keywords(of name: String, own: [String]) -> [String] {
        keywords[name] ?? own
    }

    /// Keeps `words` for a built-in engine; its own ones (or none) clear the choice.
    func setKeywords(_ words: [String]?, for name: String) {
        keywords[name] = words
        defaults.set(keywords, forKey: keywordsKey)
    }

    /// A custom engine renamed or removed: its choices follow or go.
    func rename(_ old: String, to new: String?) {
        if let shown = visibility.removeValue(forKey: old), let new { visibility[new] = shown }
        defaults.set(visibility, forKey: visibilityKey)
        if globalAI == old { globalAI = new }
    }
}
