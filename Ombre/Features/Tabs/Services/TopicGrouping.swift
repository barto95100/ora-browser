import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A tab given to the subject grouping: its number in the list, its title and
/// its site only (never its address, its page or anything typed).
struct TopicTab: Equatable, Sendable {
    let index: Int
    let title: String
    let site: String
}

/// A group of tabs on one subject, as the model suggests it.
struct TopicSuggestion: Equatable, Sendable {
    let name: String
    let indices: [Int]
}

/// Groups tabs by subject (Apple's model on the Mac; a test's own).
@MainActor
protocol TopicGrouper {
    func suggestions(for tabs: [TopicTab], language: String) async throws -> [TopicSuggestion]
}

enum TopicGrouping {
    /// Tabs of one subject that make a group, as for a site.
    static let threshold = TabGrouping.threshold
    static let maxNameLength = 40
    /// The tabs given to the model at most (it reads a few thousand words).
    static let maxTabs = 50
    /// Titles are cut there: enough to tell a subject.
    static let maxTitleLength = 80

    /// What the model said, kept only where it makes sense: tabs that exist,
    /// each in one group, groups of `threshold` tabs at least, a name.
    static func validated(_ suggestions: [TopicSuggestion], tabCount: Int) -> [TopicSuggestion] {
        var used = Set<Int>()
        return suggestions.compactMap { suggestion in
            let name = String(suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
            var indices: [Int] = []
            for index in suggestion.indices
                where (0 ..< tabCount).contains(index) && !used.contains(index) && !indices.contains(index)
            {
                indices.append(index)
            }
            guard !name.isEmpty, indices.count >= threshold else { return nil }
            used.formUnion(indices)
            return TopicSuggestion(name: name, indices: indices)
        }
    }

    /// The tabs as the model gets them.
    static func topicTabs(_ tabs: [(title: String, url: URL)]) -> [TopicTab] {
        tabs.enumerated().map { index, tab in
            TopicTab(
                index: index,
                title: String(tab.title.prefix(maxTitleLength)),
                site: TabGrouping.site(of: tab.url) ?? ""
            )
        }
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
        @Guide(description: "The numbers of the tabs in this group.") // no translation
        var tabs: [Int]
    }

    /// Apple's language model on the Mac (`SystemLanguageModel`): the tabs'
    /// titles and sites stay on the Mac.
    @available(macOS 26.0, *)
    @MainActor
    struct OnDeviceTopicGrouper: TopicGrouper {
        func suggestions(for tabs: [TopicTab], language: String) async throws -> [TopicSuggestion] {
            // For the model, never shown.
            let instructions = [
                "You sort a web browser's tabs into groups by subject.", // no translation
                "Each group holds at least \(TopicGrouping.threshold) tabs about one subject.", // no translation
                "Name each group in the language whose code is \(language)." // no translation
            ].joined(separator: " ")
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let list = tabs.map { "\($0.index). \($0.title) (\($0.site))" }.joined(separator: "\n")
            let reply = try await session.respond(to: list, generating: TopicGroupsReply.self)
            return reply.content.groups.map { TopicSuggestion(name: $0.name, indices: $0.tabs) }
        }
    }
#endif
