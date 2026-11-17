import Foundation
@testable import Ombre
import Testing

/// Subject grouping: what the model suggests is checked before use.
struct TopicGroupingTests {
    @Test func suggestionsAreChecked() {
        let tabs = (1 ... 6).map { TopicTab(id: "t\($0)", title: "Tab \($0)", site: "site\($0).example") }
        let checked = TopicGrouping.validated([
            TopicSuggestion(name: "  Travel  ", tabIDs: ["t1", " T2 ", "t2", "t9", "3"]),
            TopicSuggestion(name: "Again", tabIDs: ["t1", "t2"]),
            TopicSuggestion(name: "Alone", tabIDs: ["t1", "t3"]),
            TopicSuggestion(name: "", tabIDs: ["t4", "t5"]),
            TopicSuggestion(name: String(repeating: "x", count: 60), tabIDs: ["t4", "t5", "t6"])
        ], tabs: tabs)
        #expect(checked.map(\.tabIDs) == [["t1", "t2"], ["t4", "t5", "t6"]])
        #expect(checked.first?.name == "Travel")
        #expect(checked.last?.name.count == TopicGrouping.maxNameLength)
    }

    /// Two tabs of one site make no subject group; three do, or two sites.
    @Test func oneSiteNeedsASiteGroupsTabs() {
        let tabs = [
            TopicTab(id: "t1", title: "a", site: "search.example"),
            TopicTab(id: "t2", title: "b", site: "search.example"),
            TopicTab(id: "t3", title: "c", site: "search.example"),
            TopicTab(id: "t4", title: "d", site: "other.example"),
            TopicTab(id: "t5", title: "e", site: "search.example")
        ]
        #expect(TopicGrouping.validated([TopicSuggestion(name: "Travel", tabIDs: ["t1", "t2"])], tabs: tabs).isEmpty)
        #expect(TopicGrouping.validated([
            TopicSuggestion(name: "Travel", tabIDs: ["t1", "t2", "t3"]),
            TopicSuggestion(name: "Mixed", tabIDs: ["t4", "t5"])
        ], tabs: tabs).map(\.name) == ["Travel", "Mixed"])
        // A suggestion left out leaves its tabs to the next one.
        #expect(TopicGrouping.validated([
            TopicSuggestion(name: "Travel", tabIDs: ["t1", "t2"]),
            TopicSuggestion(name: "Mixed", tabIDs: ["t1", "t4"])
        ], tabs: tabs).map(\.tabIDs) == [["t1", "t4"]])
        // Tabs without a site (not web pages) aren't one site.
        let local = [TopicTab(id: "t1", title: "a", site: ""), TopicTab(id: "t2", title: "b", site: "")]
        #expect(TopicGrouping.validated([TopicSuggestion(name: "Notes", tabIDs: ["t1", "t2"])], tabs: local).count == 1)
    }

    /// A catch-all group (searches, a login page and an encyclopedia under
    /// "Documentation") is left out, in English or in French; a real subject stays.
    @Test(arguments: ["Web Browsing", "documentation", "Divers", "Général", " Autres "])
    func genericNamesMakeNoGroup(name: String) {
        let tabs = [
            TopicTab(id: "t1", title: "Sign in to GitHub", site: "github.com"),
            TopicTab(id: "t2", title: "Wikipedia", site: "wikipedia.org"),
            TopicTab(id: "t3", title: "Grafana", site: "grafana.com"),
            TopicTab(id: "t4", title: "Prometheus", site: "prometheus.io")
        ]
        let checked = TopicGrouping.validated([
            TopicSuggestion(name: name, tabIDs: ["t1", "t2"]),
            TopicSuggestion(name: "Supervision", tabIDs: ["t3", "t4"])
        ], tabs: tabs)
        #expect(checked == [TopicSuggestion(name: "Supervision", tabIDs: ["t3", "t4"])])
    }

    /// Only a name that says nothing else: a subject's own name stays.
    @Test func aNamedSubjectIsNotGeneric() {
        #expect(!TopicGrouping.isGeneric("Swift documentation"))
        #expect(!TopicGrouping.isGeneric("Web development"))
    }

    /// The groups are named in Ombre's language, told by its name (a code
    /// alone left them in English), and loose groups are ruled out.
    @Test func theModelIsToldTheLanguageAndNoCatchAllGroups() {
        let french = TopicGrouping.instructions(language: "fr")
        #expect(french.contains("Write every group name in French"))
        #expect(french.contains("Never make a catch-all group"))
        #expect(TopicGrouping.instructions(language: "en").contains("in English"))
    }

    /// The model gets an id, the title, the site and the page's description
    /// (cut, on one line) of each tab, never its address.
    @Test func theModelGetsIDsTitlesSitesAndDescriptionsOnly() throws {
        let tabs = try TopicGrouping.topicTabs([
            TopicSource(
                title: String(repeating: "t", count: 200),
                url: #require(URL(string: "https://mail.example.com/inbox?id=42"))
            ),
            TopicSource(title: "Second\nline", url: #require(URL(string: "https://a.org/page")), summary: " "),
            TopicSource(
                title: "Grafana",
                url: #require(URL(string: "https://grafana.com/")),
                summary: " Dashboards\nfor monitoring " + String(repeating: "d", count: 300)
            )
        ])
        #expect(tabs == [
            TopicTab(id: "t1", title: String(repeating: "t", count: 80), site: "example.com"),
            TopicTab(id: "t2", title: "Second line", site: "a.org"),
            TopicTab(
                id: "t3", title: "Grafana", site: "grafana.com",
                summary: String(("Dashboards for monitoring " + String(repeating: "d", count: 300)).prefix(160))
            )
        ])
        let lines = TopicGrouping.request(tabs).split(separator: "\n")
        #expect(lines[1] == "t2: Second line (a.org)")
        #expect(lines[2].hasPrefix("t3: Grafana (grafana.com) — Dashboards for monitoring ddd"))
    }

    @Test func theFinalMessageSaysWhatWasDone() async {
        await MainActor.run {
            #expect(TidyMessage.text(bySite: 0, bySubject: .notAsked).text == "No groups to make")
            #expect(TidyMessage.text(bySite: 1, bySubject: .made(2)).text == "3 groups made")
            #expect(TidyMessage.text(bySite: 0, bySubject: .made(0)).text == "No groups to make")
            #expect(TidyMessage.text(bySite: 0, bySubject: .failed("busy")).isFailure)
            #expect(TidyMessage.text(bySite: 2, bySubject: .failed("busy")).text.contains("busy"))
        }
    }
}

private struct GrouperFailure: Error {}

/// A grouper that fails, as the model does when it refuses or runs out of room.
@MainActor
private struct FailingGrouper: TopicGrouper {
    func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply {
        throw GrouperFailure()
    }
}

/// A grouper that answers what it is given.
@MainActor
private struct FixedGrouper: TopicGrouper {
    let reply: [TopicSuggestion]
    func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply {
        TopicReply(suggestions: reply, raw: "")
    }
}

/// A grouper that reads the request as the model does: it groups the tabs
/// whose title holds a word, by the ids written in front of them.
@MainActor
private struct KeywordGrouper: TopicGrouper {
    let subjects: [(name: String, word: String)]
    func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply {
        let lines = TopicGrouping.request(tabs).split(separator: "\n")
        let suggestions = subjects.map { subject in
            TopicSuggestion(
                name: subject.name,
                tabIDs: lines.filter { $0.contains(subject.word) }.compactMap { $0.split(separator: ":").first }
                    .map(String.init)
            )
        }
        return TopicReply(suggestions: suggestions, raw: "")
    }
}

/// A grouper that answers with positions instead of ids, counted from 0 or
/// from 1: what went wrong on a real Mac.
@MainActor
private struct PositionGrouper: TopicGrouper {
    let from: Int
    func suggestions(for tabs: [TopicTab], language: String) async throws -> TopicReply {
        let positions = (0 ..< 3).map { String($0 + from) }
        return TopicReply(suggestions: [TopicSuggestion(name: "Cooking", tabIDs: positions)], raw: "")
    }
}

extension TabManagerTests {
    @MainActor
    @Suite(.serialized)
    struct TabGroupsBySubject {
        private func makeTabs(_ window: TabManagerTestWindow, _ pages: [(title: String, address: String)]) throws
            -> [Tab]
        {
            let space = try window.activeSpace
            return try pages.enumerated().map { index, page in
                try window.tabManager.makeTab(
                    url: #require(URL(string: page.address)), title: page.title, order: 100 - index,
                    in: space, isPrivate: true
                )
            }
        }

        /// The tabs Ludo had: three recipes, three monitoring docs.
        private let recipesAndMonitoring = [
            (title: "Courgettes farcies recipe", address: "https://cuisineaz.example/1"),
            (title: "Gratin recipe", address: "https://750g.example/2"),
            (title: "Tarte recipe", address: "https://marmiton.example/3"),
            (title: "Grafana docs monitoring", address: "https://grafana.example/docs"),
            (title: "Prometheus docs monitoring", address: "https://prometheus.example/docs"),
            (title: "Zabbix monitoring: This topic does not exist yet", address: "https://zabbix.example/x")
        ]

        @Test func tidyGroupsTheTabsLeftBySubject() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tabs = try makeTabs(window, recipesAndMonitoring)
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = {
                    KeywordGrouper(subjects: [
                        (name: "Cuisine", word: "recipe"),
                        (name: "Supervision", word: "monitoring")
                    ])
                }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                let groups = window.tabManager.tabGroups(in: space)
                #expect(groups.map(\.name) == ["Cuisine", "Supervision"])
                #expect(groups.first?.tabIDs == tabs[0 ..< 3].map(\.id))
                #expect(groups.last?.tabIDs == tabs[3 ..< 6].map(\.id))
                #expect(window.tabManager.tidyingSpaceIDs.isEmpty)
            }
        }

        /// Two tabs of a subject make a group (three for a site).
        @Test func twoTabsOfASubjectMakeAGroup() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tabs = try makeTabs(window, Array(recipesAndMonitoring[3 ..< 5]))
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { KeywordGrouper(subjects: [(name: "Supervision", word: "monitoring")]) }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                #expect(window.tabManager.tabGroups(in: space).first?.tabIDs == tabs.map(\.id))
            }
        }

        /// Positions instead of ids, from 0 or from 1: never a tab taken for
        /// another, no group at all.
        @Test(arguments: [0, 1])
        func positionsInsteadOfIDsGroupNothing(from: Int) async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                _ = try makeTabs(window, recipesAndMonitoring)
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { PositionGrouper(from: from) }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                #expect(window.tabManager.tabGroups(in: space).isEmpty)
            }
        }

        /// Grouping by site first, then the tabs left by subject.
        @Test func bySiteThenBySubject() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tabs = try makeTabs(window, [
                    (title: "one", address: "https://example.com/1"),
                    (title: "a", address: "https://a.org/"),
                    (title: "two", address: "https://example.com/2"),
                    (title: "b", address: "https://b.org/"),
                    (title: "three", address: "https://example.com/3"),
                    (title: "c", address: "https://c.org/")
                ])
                let saved = TabManager.topicGrouper
                // The tabs left, in order: t1 a.org, t2 b.org, t3 c.org.
                TabManager
                    .topicGrouper = { FixedGrouper(reply: [TopicSuggestion(name: "Gardening", tabIDs: ["t1", "t3"])]) }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                let groups = window.tabManager.tabGroups(in: space)
                #expect(groups.map(\.kind) == [.site, .topic])
                #expect(groups.last?.tabIDs == [tabs[1].id, tabs[5].id])
            }
        }

        /// Two tabs of one site are no subject group (a site needs three):
        /// two searches of one search engine stay out of any group.
        @Test func twoTabsOfOneSiteMakeNoSubjectGroup() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                _ = try makeTabs(window, [
                    (title: "grafana - Search", address: "https://www.search.example/q=grafana"),
                    (title: "a", address: "https://a.org/"),
                    (title: "recipes - Search", address: "https://www.search.example/q=recipes")
                ])
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = {
                    FixedGrouper(reply: [TopicSuggestion(name: "search.example", tabIDs: ["t1", "t3"])])
                }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                #expect(window.tabManager.tabGroups(in: space).isEmpty)
            }
        }

        /// A vague title (Grafana's) with a page that says its subject: the
        /// model gets the page's description and groups it.
        @Test func aPagesDescriptionTellsItsSubject() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let grafana = try await window.openSettled("grafana")
                let page = try #require(grafana.browserPage)
                page.extensionWebView.loadHTMLString(
                    "<head><meta name=\"Description\" content=\"Dashboards for monitoring\n your systems\"></head>",
                    baseURL: URL(string: "https://grafana.example/")
                )
                let pages = TopicPageSummaries.pages(of: [grafana])
                let clock = ContinuousClock()
                let deadline = clock.now + .seconds(10)
                while await TopicPageSummaries.read(pages).isEmpty, clock.now < deadline {
                    try await Task.sleep(for: .milliseconds(50))
                }
                let summaries = await TopicPageSummaries.read(pages)
                #expect(summaries == [grafana.id: "Dashboards for monitoring\n your systems"])
                grafana.title = "Full-stack observability for the agentic era"
                let others = try makeTabs(window, Array(recipesAndMonitoring[4 ..< 6]))
                // A tab without its page: no description, nothing waited for.
                #expect(TopicPageSummaries.pages(of: others).isEmpty)
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { KeywordGrouper(subjects: [(name: "Supervision", word: "monitoring")]) }
                defer { TabManager.topicGrouper = saved }

                await window.tabManager.tidyTabs(in: space)?.value

                let groups = window.tabManager.tabGroups(in: space)
                #expect(groups.map(\.name) == ["Supervision"])
                #expect(Set(groups.first?.tabIDs ?? []) == Set([grafana.id] + others.map(\.id)))
            }
        }

        /// A click while the model works is ignored: one request at a time.
        @Test func aSecondTidyWaitsForTheFirst() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                _ = try makeTabs(window, recipesAndMonitoring)
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { KeywordGrouper(subjects: [(name: "Cuisine", word: "recipe")]) }
                defer { TabManager.topicGrouper = saved }

                let first = window.tabManager.tidyTabs(in: space)
                #expect(first != nil)
                #expect(window.tabManager.tidyingSpaceIDs == [space.id])
                #expect(window.tabManager.tidyTabs(in: space) == nil)
                await first?.value
                #expect(window.tabManager.tabGroups(in: space).count == 1)
                #expect(window.tabManager.tidyingSpaceIDs.isEmpty)
            }
        }

        /// The model fails: the groups by site stay, nothing else changes.
        @Test func aFailingModelLeavesTheSiteGroups() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                _ = try makeTabs(window, [
                    (title: "1", address: "https://example.com/1"),
                    (title: "2", address: "https://example.com/2"),
                    (title: "3", address: "https://example.com/3"),
                    (title: "a", address: "https://a.org/"),
                    (title: "b", address: "https://b.org/"),
                    (title: "c", address: "https://c.org/")
                ])
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { FailingGrouper() }
                defer { TabManager.topicGrouper = saved }
                await window.tabManager.tidyTabs(in: space)?.value
                #expect(window.tabManager.tabGroups(in: space).map(\.kind) == [.site])
                #expect(window.tabManager.tidyingSpaceIDs.isEmpty)
            }
        }

        /// Without the model (another Mac, Apple Intelligence off): by site only.
        @Test func withoutTheModelOnlyBySite() async throws {
            try await TabManagerTestWindow.run { window in
                let saved = TabManager.topicGrouper
                TabManager.topicGrouper = { nil }
                defer { TabManager.topicGrouper = saved }
                let space = try window.activeSpace
                #expect(window.tabManager.tidyTabs(in: space) == nil)
            }
        }
    }
}
