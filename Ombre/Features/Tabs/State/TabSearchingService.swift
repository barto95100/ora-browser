import SwiftData
import SwiftUI
import WebKit

// MARK: - Tab Searching Providing

protocol TabSearchingProviding {
    func search(
        _ text: String,
        activeContainer: TabContainer?,
        modelContext: ModelContext
    ) -> [Tab]
}

// MARK: - Tab Searching Service

final class TabSearchingService: TabSearchingProviding {
    func search(
        _ text: String,
        activeContainer: TabContainer? = nil,
        modelContext: ModelContext
    ) -> [Tab] {
        // No space: no tab (never those of all the spaces).
        guard let activeContainerId = activeContainer?.id else { return [] }
        let trimmedText = text.trimmingCharacters(in: .whitespaces)

        // The space's tabs, then those matching: by their name, their page's
        // real title or their address (see `TabName`).
        let predicate = #Predicate<Tab> { tab in tab.parentContainer?.id == activeContainerId }
        guard var results = try? modelContext.fetch(FetchDescriptor<Tab>(predicate: predicate)) else {
            return []
        }
        if !trimmedText.isEmpty {
            results = results.filter { tab in
                tab.urlString.localizedStandardContains(trimmedText)
                    || TabName.matches(trimmedText, customName: tab.customName, pageTitle: tab.title)
            }
        }
        let query = trimmedText.lowercased()
        return Self.ranked(
            results,
            match: { tab in
                max(
                    Self.scoreMatch(title: tab.title, url: tab.urlString, query: query),
                    tab.customName.map { Self.scoreMatch(title: $0, url: "", query: query) } ?? 0
                )
            },
            accessedAt: \.lastAccessedAt
        )
    }

    /// The best match first; between equal matches, the most recently used.
    /// Each score is computed once.
    nonisolated static func ranked<T>(
        _ items: [T],
        match: (T) -> Int,
        accessedAt: (T) -> Date?
    ) -> [T] {
        items
            .map { (item: $0, match: match($0), accessedAt: accessedAt($0) ?? .distantPast) }
            .sorted { $0.match != $1.match ? $0.match > $1.match : $0.accessedAt > $1.accessedAt }
            .map(\.item)
    }

    /// How well a tab's title or address matches `query` (lowercased).
    nonisolated static func scoreMatch(title: String, url: String, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        func score(_ field: String) -> Int {
            if field == query { return 100 }
            if field.hasPrefix(query) { return 90 }
            if field.contains(query) { return 75 }
            if !field.isEmpty, query.contains(field) { return 50 }
            return 0
        }
        return max(score(title.lowercased()), score(url.lowercased()))
    }
}
