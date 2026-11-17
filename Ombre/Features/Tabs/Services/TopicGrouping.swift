import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A tab given to the subject grouping: a short id of its own ("t1", "t2"…),
/// its title, its site and the description its page gives of itself, if
/// loaded (never its address, its text or anything typed).
/// The model answers with these ids, never with positions: a reply counted
/// from 0 or from 1 can't take one tab for another.
struct TopicTab: Equatable, Sendable {
    let id: String
    let title: String
    let site: String
    /// The page's description (its meta description), if any: a vague title
    /// ("Full-stack observability…") says its subject there.
    var summary = ""

    /// The line the model reads for this tab.
    var line: String {
        let line = "\(id): \(title) (\(site))"
        return summary.isEmpty ? line : line + " — " + summary
    }
}

/// What a tab gives the subject grouping, before it is cut to one line.
struct TopicSource {
    let title: String
    let url: URL
    var summary = ""
}

/// A group of tabs on one subject, as the model suggests it (tab ids).
struct TopicSuggestion: Equatable, Sendable {
    let name: String
    let tabIDs: [String]
}

/// What the model answered: its groups, and its reply as it came (for a
/// diagnosis).
struct TopicReply: Sendable {
    let suggestions: [TopicSuggestion]
    let raw: String
}

/// Groups tabs by subject (Apple's model on the Mac; a test's own).
@MainActor
protocol TopicGrouper {
    func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply
}

enum TopicGrouping {
    /// Tabs of one subject that make a group: two, unlike a site (three),
    /// or small subjects would never be grouped.
    static let threshold = 2
    static let maxNameLength = 40
    /// The tabs given to the model at most (it reads a few thousand words).
    static let maxTabs = 50
    /// Titles are cut there: enough to tell a subject.
    static let maxTitleLength = 80
    /// Descriptions are cut there (search engines show about as much).
    static let maxSummaryLength = 160
    /// The model's answer is no longer waited for after that.
    static let deadline: Duration = .seconds(60)

    /// What the model said, kept only where it makes sense: ids given to it
    /// (others ignored), each tab in one group, groups of `threshold` tabs at
    /// least, a name. A group of one site's tabs only is a site's group: it
    /// needs `TabGrouping.threshold` tabs, as by site (two searches of one
    /// search engine are no subject).
    static func validated(_ suggestions: [TopicSuggestion], tabs: [TopicTab]) -> [TopicSuggestion] {
        let sites = Dictionary(tabs.map { ($0.id, $0.site) }, uniquingKeysWith: { first, _ in first })
        let known = Set(sites.keys)
        var used = Set<String>()
        return suggestions.compactMap { suggestion in
            let name = String(suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
            var ids: [String] = []
            for raw in suggestion.tabIDs {
                let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard known.contains(id), !used.contains(id), !ids.contains(id) else { continue }
                ids.append(id)
            }
            guard !name.isEmpty, !isGeneric(name), ids.count >= threshold else { return nil }
            let groupSites = Set(ids.map { sites[$0] ?? "" })
            if groupSites.count == 1, groupSites.first?.isEmpty == false, ids.count < TabGrouping.threshold {
                return nil
            }
            used.formUnion(ids)
            return TopicSuggestion(name: name, tabIDs: ids)
        }
    }

    /// Names that say no subject: the group they make gathers tabs with
    /// nothing in common (searches, a login page and an encyclopedia).
    private static let genericNames: Set<String> = [
        "web browsing", "browsing", "websites", "web pages", "pages", "tabs", "documentation", "docs", // no translation
        "search", "searches", "research", "login", "sign in", "misc", "miscellaneous", "other", // no translation
        "others", "various", "general", "reading", "resources", "navigation web", "sites web", // no translation
        "pages web", "onglets", "recherche", "recherches", "connexion", "divers", "autre", "autres", // no translation
        "lecture", "ressources" // no translation
    ]

    /// A name of `genericNames`, whatever its case and accents.
    static func isGeneric(_ name: String) -> Bool {
        genericNames.contains(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    /// What the model is told (never shown): the groups' language by its
    /// English name (a code alone left the names in English) and no group
    /// without a real subject.
    static func instructions(language: String) -> String {
        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language
        return [
            "You sort a web browser's tabs into groups by subject.", // no translation
            "Each line is a tab: its id, a colon, its title and its site,", // no translation
            "sometimes followed by a dash and the page's description.", // no translation
            "Make a group only for tabs that clearly share one real, specific subject,", // no translation
            "at least \(threshold) tabs each.", // no translation
            "Leave out every tab that shares no such subject with others:", // no translation
            "leaving tabs out is better than a loose group.", // no translation
            "Never make a catch-all group, and never give a group a generic name", // no translation
            "such as Web Browsing, Documentation, Search, Login, Miscellaneous or Other.", // no translation
            "Give the tabs by their ids, exactly as written.", // no translation
            "Write every group name in \(languageName), whatever the language of the tabs." // no translation
        ].joined(separator: " ")
    }

    /// The tabs as the model gets them, numbered from "t1".
    static func topicTabs(_ tabs: [TopicSource]) -> [TopicTab] {
        tabs.enumerated().map { index, tab in
            TopicTab(
                id: "t\(index + 1)",
                title: oneLine(tab.title, maxTitleLength),
                site: TabGrouping.site(of: tab.url) ?? "",
                summary: oneLine(tab.summary, maxSummaryLength)
            )
        }
    }

    /// One line per tab, whatever the page wrote.
    private static func oneLine(_ text: String, _ length: Int) -> String {
        String(text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces).prefix(length))
    }

    /// What the model reads: one tab per line.
    static func request(_ tabs: [TopicTab]) -> String {
        tabs.map(\.line).joined(separator: "\n")
    }

    /// The model on this Mac, if it can be used now (macOS 26, Apple
    /// Intelligence on, model downloaded). Never a model online.
    @MainActor
    static var onDeviceGrouper: (any TopicGrouper)? {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
                return OnDeviceTopicGrouper()
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    struct TopicGroupsReply {
        @Guide(description: "Groups of tabs, one specific subject each; tabs fitting none left out.") // no translation
        var groups: [TopicGroupReply]
    }

    @available(macOS 26.0, *)
    @Generable
    struct TopicGroupReply {
        @Guide(description: "A short, specific name for the subject, two or three words.") // no translation
        var name: String
        @Guide(description: "The ids of the tabs in this group, exactly as given (t1, t2…).") // no translation
        var tabs: [String]
    }

    /// Apple's language model on the Mac (`SystemLanguageModel`): the tabs'
    /// titles and sites stay on the Mac.
    @available(macOS 26.0, *)
    @MainActor
    struct OnDeviceTopicGrouper: TopicGrouper {
        func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply {
            let instructions = TopicGrouping.instructions(language: language)
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let reply = try await session.respond(to: TopicGrouping.request(tabs), generating: TopicGroupsReply.self)
            return TopicReply(
                suggestions: reply.content.groups.map { TopicSuggestion(name: $0.name, tabIDs: $0.tabs) },
                raw: reply.rawContent.jsonString
            )
        }
    }
#endif
