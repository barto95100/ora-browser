import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// A search goes to the engine chosen, never elsewhere (SEC-25); open tabs
/// are ranked by how well they match first (ONG-15).
struct SearchFallbackTests {
    private func engine(_ name: String, _ address: String) -> SearchEngine {
        SearchEngine(name: name, color: .blue, icon: "", aliases: [], searchURL: address, isAIChat: false)
    }

    @Test func theSpacesEngineComesFirst() {
        let url = SearchEngineService.firstSearchURL(for: "a b", engines: [
            engine("DuckDuckGo", "https://duckduckgo.com/?q={query}"),
            engine("Ecosia", "https://www.ecosia.org/search?q={query}")
        ])
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=a%20b")
    }

    /// The space's engine can't make an address: the one for all spaces.
    @Test func thenTheEngineForAllSpaces() {
        let url = SearchEngineService.firstSearchURL(for: "ombre", engines: [
            engine("Broken", "not a url {query}"), nil,
            engine("Ecosia", "https://www.ecosia.org/search?q={query}")
        ])
        #expect(url?.host == "www.ecosia.org")
    }

    /// It used to go to Google.
    @Test func neverAnotherEngine() {
        #expect(SearchEngineService.firstSearchURL(for: "ombre", engines: [
            engine("Broken", "not a url {query}"), engine("Local", "file:///tmp/{query}"), nil
        ]) == nil)
    }

    /// The settings refuse a template Ombre would never search with; they
    /// used to accept any address, `file:` and `javascript:` included.
    @Test func theSettingsOnlyAcceptWebTemplates() {
        #expect(SearchEngineService.isValidTemplate("https://duckduckgo.com/?q={query}"))
        #expect(SearchEngineService.isValidTemplate("HTTP://intranet.example/search?q={query}"))
        for template in [
            "file:///tmp/{query}", "javascript:alert('{query}')", "ombre://search?q={query}",
            "https:///?q={query}", "https://example.com/search", "example.com/?q={query}", ""
        ] {
            #expect(!SearchEngineService.isValidTemplate(template), "\(template)")
        }
    }

    /// An engine saved before the settings checked it: its alias doesn't
    /// open a `file:` or `javascript:` address either.
    @Test func anAliasOnlyOpensWebAddresses() {
        #expect(SearchEngineService.searchURL(template: "https://example.com/?q={query}", query: "a b")?
            .absoluteString == "https://example.com/?q=a%20b")
        #expect(SearchEngineService.searchURL(template: "file:///tmp/{query}", query: "ombre") == nil)
        #expect(SearchEngineService.searchURL(template: "javascript:alert('{query}')", query: "ombre") == nil)
    }

    private struct Item {
        let name: String
        let title: String
        let accessedAt: Date?
    }

    private func ranked(_ items: [Item], query: String) -> [String] {
        TabSearchingService.ranked(
            items,
            match: { TabSearchingService.scoreMatch(title: $0.title, url: "", query: query) },
            accessedAt: \.accessedAt
        ).map(\.name)
    }

    /// An exact title used two days ago goes before a tab that only contains
    /// the text, used an hour ago (recency used to win).
    @Test func theBestMatchComesFirst() {
        let now = Date()
        let items = [
            Item(name: "recent", title: "my weather notes", accessedAt: now.addingTimeInterval(-3600)),
            Item(name: "exact", title: "Weather", accessedAt: now.addingTimeInterval(-2 * 86400))
        ]
        #expect(ranked(items, query: "weather") == ["exact", "recent"])
    }

    @Test func recencySettlesEqualMatches() {
        let now = Date()
        let items = [
            Item(name: "never", title: "Weather", accessedAt: nil),
            Item(name: "old", title: "Weather", accessedAt: now.addingTimeInterval(-86400)),
            Item(name: "new", title: "Weather", accessedAt: now)
        ]
        #expect(ranked(items, query: "weather") == ["new", "old", "never"])
    }

    /// A tab with no title doesn't match everything.
    @Test func anEmptyTitleIsNoMatch() {
        #expect(TabSearchingService.scoreMatch(title: "", url: "", query: "weather") == 0)
    }
}
