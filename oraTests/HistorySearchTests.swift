import Foundation
@testable import Ora
import SwiftData
import Testing

/// History search, filtered by the database (launcher and history panel).
@MainActor
struct HistorySearchTests {
    private let container = DatabaseRecovery.inMemoryContainer()
    private let context: ModelContext
    private let manager: HistoryManager
    private let space: TabContainer
    private let otherSpace: TabContainer

    init() {
        context = ModelContext(container)
        manager = HistoryManager(modelContainer: container, modelContext: context)
        space = TabContainer(name: "Space", isActive: true)
        otherSpace = TabContainer(name: "Other", isActive: false)
        context.insert(space)
        context.insert(otherSpace)
    }

    /// An entry visited `minutesAgo` minutes ago.
    private func add(_ address: String, title: String, minutesAgo: Double, in container: TabContainer? = nil) {
        guard let url = URL(string: address) else { return }
        let entry = History(
            url: url, title: title, faviconURL: url,
            createdAt: Date(), lastAccessedAt: Date(), visitCount: 1,
            container: container ?? space
        )
        // `History.init` dates the entry now, whatever it is given.
        entry.lastAccessedAt = Date(timeIntervalSinceNow: -minutesAgo * 60)
        context.insert(entry)
    }

    private func titles(_ text: String, limit: Int = 50) -> [String] {
        manager.search(text, activeContainerId: space.id, limit: limit).map(\.title)
    }

    @Test func matchesAddressOrTitleIgnoringCaseAndAccents() {
        add("https://github.com/apple", title: "Apple on GitHub", minutesAgo: 1)
        add("https://example.com/cafe", title: "Le Café", minutesAgo: 2)
        add("https://news.example.org", title: "News", minutesAgo: 3)
        try? context.save()

        #expect(titles("GITHUB") == ["Apple on GitHub"])
        #expect(titles("café") == ["Le Café"])
        #expect(titles("cafe") == ["Le Café"])
        #expect(titles("news") == ["News"])
        #expect(titles("  news ") == ["News"])
        #expect(titles("nothing").isEmpty)
    }

    @Test func mostRecentFirstWithinTheLimit() {
        add("https://a.example.com", title: "Old", minutesAgo: 30)
        add("https://b.example.com", title: "Recent", minutesAgo: 1)
        add("https://c.example.com", title: "Middle", minutesAgo: 10)
        try? context.save()

        #expect(titles("example") == ["Recent", "Middle", "Old"])
        #expect(titles("example", limit: 2) == ["Recent", "Middle"])
        // No text: the latest entries.
        #expect(titles("", limit: 1) == ["Recent"])
    }

    @Test func onlyTheActiveSpace() {
        add("https://shared.example.com/mine", title: "Mine", minutesAgo: 1)
        add("https://shared.example.com/theirs", title: "Theirs", minutesAgo: 1, in: otherSpace)
        try? context.save()

        #expect(titles("shared") == ["Mine"])
    }

    /// A visit to a page already in the space's history counts on its entry.
    @Test func recordingAVisitAgainUpdatesTheEntry() throws {
        let url = try #require(URL(string: "https://visited.example.com"))
        manager.record(title: "Visited", url: url, container: space)
        manager.record(title: "Visited", url: url, container: space)

        let entries = manager.search("visited", activeContainerId: space.id, limit: 10)
        #expect(entries.count == 1)
        #expect(entries.first?.visitCount == 2)
    }
}
