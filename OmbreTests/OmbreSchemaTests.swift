import Foundation
import SwiftData
import Testing
@testable import Ombre

@MainActor
struct OmbreSchemaTests {
    @Test func historyKeepsTheDatesItIsGiven() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let accessed = Date(timeIntervalSince1970: 1_750_000_000)
        let entry = try History(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
            faviconURL: #require(URL(string: "https://example.com/favicon.ico")),
            createdAt: created,
            lastAccessedAt: accessed,
            visitCount: 3
        )
        #expect(entry.createdAt == created)
        #expect(entry.lastAccessedAt == accessed)
    }
}

extension TabManagerTests {
    @MainActor
    struct SchemaV1 {
        private let schema = ModelConfiguration.mainSchema

        private func entity(_ name: String) -> Schema.Entity? {
            schema.entities.first { $0.name == name }
        }

        @Test func listsEveryModel() {
            let names = Set(schema.entities.map(\.name))
            #expect(names == ["TabContainer", "Tab", "Folder", "SpaceTask", "History", "Download"])
        }

        @Test(arguments: ["TabContainer", "Tab", "Folder", "SpaceTask", "History", "Download"])
        func identifiersAreUnique(_ name: String) {
            let id = entity(name)?.attributes.first { $0.name == "id" }
            #expect(id?.isUnique == true)
        }

        @Test func spaceRelationshipsAreOptional() {
            for name in ["Tab", "Folder"] {
                let relationship = entity(name)?.relationships.first { $0.name == "parentContainer" }
                #expect(relationship?.isOptional == true, "\(name)")
            }
        }

        @Test func spaceHistoryGoesWithTheSpace() {
            let history = entity("TabContainer")?.relationships.first { $0.name == "history" }
            #expect(history?.deleteRule == .cascade)
        }

        @Test func databaseLivesInTheOmbreFolder() {
            let url = ModelConfiguration.mainDatabaseURL
            #expect(url.lastPathComponent == "OmbreData.sqlite")
            #expect(url.deletingLastPathComponent().lastPathComponent == "Ombre")
        }

        @Test func newSpacesGoLast() async throws {
            try await TabManagerTestWindow.run { window in
                let first = window.createSpace("First")
                let second = window.createSpace("Second")
                #expect(second.order == first.order + 1)
                let sorted = try window.modelContext
                    .fetch(FetchDescriptor<TabContainer>(sortBy: TabContainer.displayOrder))
                let names = sorted.map(\.name).filter { ["First", "Second"].contains($0) }
                #expect(names == ["First", "Second"])
            }
        }
    }
}

extension TabManagerTests {
    /// The launcher's search among the active space's tabs.
    @MainActor
    struct TabSearch {
        @Test func findsTheActiveSpacesTabsByTitleOrAddress() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let other = window.createSpace("Other")
                let byTitle = window.addUnloadedTab("first", order: 1, in: space)
                byTitle.title = "Weather forecast"
                let byAddress = window.addUnloadedTab("weather-page", order: 2, in: space)
                let elsewhere = window.addUnloadedTab("weather-other", order: 1, in: other)
                elsewhere.title = "Weather elsewhere"
                window.tabManager.activateContainer(space)
                try window.modelContext.save()

                let found = Set(window.tabManager.search("weather").map(\.id))

                #expect(found == [byTitle.id, byAddress.id])
            }
        }
    }
}
