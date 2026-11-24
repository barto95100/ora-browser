import Foundation
@testable import Ombre
import SwiftData
import Testing

/// A tab's name, like Arc's Rename (see `TabName`).
struct TabNameTests {
    @Test func aGivenNameIsShownInsteadOfThePagesTitle() {
        #expect(TabName.displayed(customName: "Board", pageTitle: "Sprint 42 – Jira") == "Board")
        #expect(TabName.displayed(customName: nil, pageTitle: "Sprint 42 – Jira") == "Sprint 42 – Jira")
    }

    @Test func anEmptyNameGoesBackToThePagesTitle() {
        #expect(TabName.stored(fromTyped: "") == nil)
        #expect(TabName.stored(fromTyped: "   \n") == nil)
        #expect(TabName.stored(fromTyped: "  Board ") == "Board")
    }

    @Test func aSearchFindsTheNameAndThePagesRealTitle() {
        #expect(TabName.matches("board", customName: "Board", pageTitle: "Sprint 42 – Jira"))
        #expect(TabName.matches("jira", customName: "Board", pageTitle: "Sprint 42 – Jira"))
        #expect(!TabName.matches("mail", customName: "Board", pageTitle: "Sprint 42 – Jira"))
        #expect(TabName.matches("jira", customName: nil, pageTitle: "Sprint 42 – Jira"))
    }

    /// V2 and V3 differ by the tab's name only: the frozen classes are V2's.
    @Test func theNewSchemaOnlyAddsTheTabsName() {
        let before = Schema(versionedSchema: OmbreSchemaV2.self)
        let after = Schema(versionedSchema: OmbreSchemaV3.self)
        func properties(_ schema: Schema) -> [String: Set<String>] {
            Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
                (entity.name, Set(entity.attributes.map(\.name) + entity.relationships.map(\.name)))
            })
        }
        var expected = properties(before)
        expected["Tab", default: []].insert("customName")
        #expect(properties(after) == expected)
    }
}

extension TabManagerTests {
    @MainActor
    struct Rename {
        @Test func aNameStaysWhateverThePageShowsAndIsSaved() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("page", order: 1, in: space)
                window.tabManager.renameTab(tab, to: "  My page ")
                #expect(tab.customName == "My page")
                // Saved at once.
                #expect(!window.modelContext.hasChanges)
                // The page changes its title, or goes elsewhere: the name stays.
                tab.title = "Another title"
                tab.url = TabManagerTestWindow.url("elsewhere")
                #expect(tab.displayName == "My page")
                // An empty name: back to the page's title.
                window.tabManager.renameTab(tab, to: "")
                #expect(tab.customName == nil)
                #expect(tab.displayName == "Another title")
            }
        }

        @Test func aDuplicateKeepsTheName() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("page", order: 1, in: space)
                window.tabManager.renameTab(tab, to: "Mine")
                window.tabManager.duplicateTab(tab)
                let names = space.tabs.filter { $0.url == tab.url }.map(\.customName)
                #expect(names == ["Mine", "Mine"])
            }
        }

        @Test func aReopenedTabKeepsItsName() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("page", order: 1, in: space)
                window.tabManager.renameTab(tab, to: "Mine")
                let id = tab.id
                await window.close(tab)
                window.tabManager.restoreLastTab()
                #expect(window.tabs(withID: id).map(\.customName) == ["Mine"])
            }
        }

        @Test func theLaunchersSearchFindsTheNameAndTheTitle() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("sprint-board", order: 1, in: space)
                tab.title = "Sprint 42 – Jira"
                window.tabManager.renameTab(tab, to: "Board")
                let search = TabSearchingService()
                for query in ["board", "jira"] {
                    let found = search.search(query, activeContainer: space, modelContext: window.modelContext)
                    #expect(found.map(\.id) == [tab.id], "\(query)")
                }
            }
        }

        @Test func agentsGetTheNameBesideThePagesTitle() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("page", order: 1, in: space)
                tab.title = "Page title"
                window.tabManager.renameTab(tab, to: "Mine")
                let agentTab = AgentCommands.agentTab(tab, in: window.tabManager)
                #expect(agentTab.title == "Page title")
                #expect(agentTab.name == "Mine")
            }
        }
    }
}
