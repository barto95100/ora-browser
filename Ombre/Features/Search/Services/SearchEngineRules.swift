import Foundation

/// Which engines show, which keyword opens which engine, and which AI a space
/// asks: apart from the settings that hold the choices, to be tested alone.
///
/// The engine and the AI used by default, and those a space chooses, always
/// show (they cannot be hidden).
struct SearchEngineRules {
    /// Ombre's engine when none is chosen.
    static let fallbackSearch = "Google" // no translation

    /// Every engine, built-in then custom, with its keywords as chosen.
    var engines: [SearchEngine]
    /// Shown as chosen in the settings (or by default).
    var isChosenShown: (String) -> Bool
    /// The engine for all spaces; nil: `fallbackSearch`.
    var globalSearch: String?
    /// The AI for all spaces; nil: `SearchEnginePreferences.fallbackAI`.
    var globalAI: String?
    /// The engines and AIs chosen by a space.
    var spaceChoices: Set<String> = []

    var defaultSearchName: String {
        globalSearch ?? Self.fallbackSearch
    }

    var defaultAIName: String {
        globalAI ?? SearchEnginePreferences.fallbackAI
    }

    /// The default engine or AI: always shown.
    func isDefault(_ name: String) -> Bool {
        name == defaultSearchName || name == defaultAIName
    }

    /// Used by default or by a space: cannot be hidden.
    func isLocked(_ name: String) -> Bool {
        isDefault(name) || spaceChoices.contains(name)
    }

    func isShown(_ name: String) -> Bool {
        isLocked(name) || isChosenShown(name)
    }

    /// The shown engine a keyword opens (the first one with it), if any.
    func engine(forKeyword keyword: String) -> SearchEngine? {
        let word = keyword.lowercased()
        return engines.first { isShown($0.name) && $0.aliases.contains(word) }
    }

    /// An engine offered for what is typed: the start of one of its keywords.
    struct KeywordMatch {
        let engine: SearchEngine
        /// Its keyword that begins with what is typed (the shortest one).
        let keyword: String
        let isExact: Bool
    }

    /// The shown engines one of whose keywords begins with `typed`, best
    /// first (an exact keyword, then the shortest one), `limit` at most.
    /// Two letters at least, unless a keyword is exactly that.
    func keywordMatches(for typed: String, limit: Int = 2) -> [KeywordMatch] {
        let text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return [] }
        let matches = engines.enumerated().compactMap { index, engine -> (KeywordMatch, Int)? in
            guard isShown(engine.name) else { return nil }
            let candidates = engine.aliases.filter { $0.hasPrefix(text) }
            guard let best = candidates.min(by: { $0.count < $1.count }) else { return nil }
            let isExact = best == text
            guard isExact || text.count >= 2 else { return nil }
            return (KeywordMatch(engine: engine, keyword: best, isExact: isExact), index)
        }
        return matches
            .sorted { lhs, rhs in
                if lhs.0.isExact != rhs.0.isExact { return lhs.0.isExact }
                if lhs.0.keyword.count != rhs.0.keyword.count { return lhs.0.keyword.count < rhs.0.keyword.count }
                return lhs.1 < rhs.1
            }
            .prefix(limit)
            .map(\.0)
    }

    /// The AI a space asks: its own, else the one for all spaces, else
    /// ChatGPT. A choice that is gone, or not an AI, is passed over.
    func aiEngine(spaceChoice: String?) -> SearchEngine? {
        let names = [spaceChoice, globalAI, SearchEnginePreferences.fallbackAI].compactMap(\.self)
        for name in names {
            if let engine = engines.first(where: { $0.name == name && $0.isAIChat }) { return engine }
        }
        return nil
    }

    /// The engines other than `name`, shown or not, that already use one of
    /// `keywords`: keyword → that engine's name (a hidden one shown again
    /// would take its keyword back).
    func conflicts(of keywords: [String], for name: String) -> [String: String] {
        var found: [String: String] = [:]
        for word in keywords {
            if let other = engines.first(where: { $0.name != name && $0.aliases.contains(word) }) {
                found[word] = other.name
            }
        }
        return found
    }

    /// Keywords as typed in the settings ("yt, you tube"): separated by
    /// commas, lowercase, without repeats.
    static func keywords(from text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// An address as typed for a custom engine: `%s` stands for the search,
    /// like in Safari and Chrome; kept as `{query}`.
    static func template(from address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%s", with: "{query}")
    }
}
