import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A tab given to the subject grouping: a short id of its own ("t1", "t2"…),
/// its title and its site only (never its address, its page or anything typed).
/// The model answers with these ids, never with positions: a reply counted
/// from 0 or from 1 can't take one tab for another.
struct TopicTab: Equatable, Sendable {
    let id: String
    let title: String
    let site: String

    /// The line the model reads for this tab.
    var line: String {
        "\(id): \(title) (\(site))"
    }
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
    /// The model's answer is no longer waited for after that.
    static let deadline: Duration = .seconds(60)

    /// What the model said, kept only where it makes sense: ids given to it
    /// (others ignored), each tab in one group, groups of `threshold` tabs at
    /// least, a name.
    static func validated(_ suggestions: [TopicSuggestion], known: Set<String>) -> [TopicSuggestion] {
        var used = Set<String>()
        return suggestions.compactMap { suggestion in
            let name = String(suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
            var ids: [String] = []
            for raw in suggestion.tabIDs {
                let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard known.contains(id), !used.contains(id), !ids.contains(id) else { continue }
                ids.append(id)
            }
            guard !name.isEmpty, ids.count >= threshold else { return nil }
            used.formUnion(ids)
            return TopicSuggestion(name: name, tabIDs: ids)
        }
    }

    /// The tabs as the model gets them, numbered from "t1".
    static func topicTabs(_ tabs: [(title: String, url: URL)]) -> [TopicTab] {
        tabs.enumerated().map { index, tab in
            TopicTab(
                id: "t\(index + 1)",
                // One line per tab, whatever the title holds.
                title: String(tab.title.replacing(/\s+/, with: " ").prefix(maxTitleLength)),
                site: TabGrouping.site(of: tab.url) ?? ""
            )
        }
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
        @Guide(description: "Groups of tabs, one subject each; tabs fitting none left out.") // no translation
        var groups: [TopicGroupReply]
    }

    @available(macOS 26.0, *)
    @Generable
    struct TopicGroupReply {
        @Guide(description: "A short name for the subject, two or three words.") // no translation
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
            // For the model, never shown.
            let instructions = [
                "You sort a web browser's tabs into groups by subject.", // no translation
                "Each line is a tab: its id, a colon, its title and its site.", // no translation
                "Each group holds at least \(TopicGrouping.threshold) tabs about one subject.", // no translation
                "Give the tabs by their ids, exactly as written.", // no translation
                "Name each group in the language whose code is \(language)." // no translation
            ].joined(separator: " ")
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let reply = try await session.respond(to: TopicGrouping.request(tabs), generating: TopicGroupsReply.self)
            return TopicReply(
                suggestions: reply.content.groups.map { TopicSuggestion(name: $0.name, tabIDs: $0.tabs) },
                raw: reply.rawContent.jsonString
            )
        }
    }
#endif
