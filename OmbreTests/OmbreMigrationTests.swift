import Foundation
@testable import Ombre
import SwiftData
import Testing

/// Finds the test bundle's resources.
private final class FixtureToken {}

/// The plan of the builds before tab groups: V1 only.
private enum PlanBeforeGroups: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OmbreSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// The user's database, made by an earlier build, opens with tab groups:
/// nothing lost, groups can be added. A failure would move it aside
/// (`DatabaseRecovery`) and the user would start again from an empty one.
@MainActor
struct OmbreMigrationTests {
    private func temporaryStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OmbreMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "OmbreData.sqlite")
    }

    @Test func aVersionOneDatabaseOpensWithTabGroups() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let spaceID: UUID
        let tabID: UUID
        do {
            let schema = Schema(versionedSchema: OmbreSchemaV1.self)
            let old = try ModelContainer(
                for: schema,
                migrationPlan: PlanBeforeGroups.self,
                configurations: ModelConfiguration("OmbreData", schema: schema, url: url)
            )
            let context = ModelContext(old)
            // V1's own classes (frozen), as that build stored them.
            let space = OmbreSchemaV1.TabContainer(name: "Work")
            context.insert(space)
            let folder = OmbreSchemaV1.Folder(name: "Reading", isOpened: true, container: space)
            folder.order = 3
            context.insert(folder)
            try context.save()
            spaceID = space.id
            tabID = folder.id
        }

        let container = try ModelConfiguration.createMainContainer(at: url)
        let context = ModelContext(container)
        let spaces = try context.fetch(FetchDescriptor<TabContainer>())
        #expect(spaces.map(\.id) == [spaceID])
        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.map(\.id) == [tabID])
        #expect(folders.first?.order == 3 && folders.first?.parentContainer?.id == spaceID)

        context.insert(TabGroup(
            spaceID: spaceID,
            name: "example.com",
            kind: .site,
            siteKey: "example.com",
            tabIDs: [tabID]
        ))
        try context.save()
        let reopened = try ModelContext(ModelConfiguration.createMainContainer(at: url))
        let groups = try reopened.fetch(FetchDescriptor<TabGroup>())
        #expect(groups.map(\.tabIDs) == [[tabID]])
    }

    /// A database written by the build before tab groups (`main` at
    /// ce2520a: two spaces, a folder, three tabs, a history entry, a task),
    /// opened by this one.
    @Test func aDatabaseOfTheBuildBeforeOpens() throws {
        let fixture = try #require(Bundle(for: FixtureToken.self).url(
            forResource: "OmbreData-v1",
            withExtension: "sqlite"
        ))
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.copyItem(at: fixture, to: url)

        let context = try ModelContext(ModelConfiguration.createMainContainer(at: url))
        // The default space made by its first window, and "Work".
        let spaces = try context.fetch(FetchDescriptor<TabContainer>(sortBy: TabContainer.displayOrder))
        #expect(spaces.count == 2)
        let work = try #require(spaces.first { $0.name == "Work" })
        let tabs = try context.fetch(FetchDescriptor<Tab>(sortBy: [SortDescriptor(\.order)]))
        #expect(tabs.map(\.url.absoluteString) == [
            "https://example.com/a",
            "https://example.com/b",
            "https://other.org/"
        ])
        #expect(tabs.map(\.type) == [.pinned, .normal, .normal])
        #expect(tabs.allSatisfy { $0.parentContainer?.id == work.id })
        #expect(try context.fetch(FetchDescriptor<Folder>()).map(\.name) == ["Reading"])
        #expect(try context.fetch(FetchDescriptor<History>()).map(\.visitCount) == [2])
        #expect(try context.fetch(FetchDescriptor<SpaceTask>()).map(\.title) == ["Task"])
        context.insert(TabGroup(spaceID: work.id, name: "example.com", kind: .site, tabIDs: tabs.map(\.id)))
        try context.save()
    }

    /// A database written by the build before tab names (`main` at
    /// 482d060: a space, a folder, a pinned, a normal and a favorite tab, a
    /// group, a history entry, a task), opened by this one: nothing lost,
    /// every tab without a name of its own, and a name kept once given.
    @Test func aDatabaseOfTheBuildBeforeTabNamesOpens() throws {
        let fixture = try #require(Bundle(for: FixtureToken.self).url(
            forResource: "OmbreData-v2",
            withExtension: "sqlite"
        ))
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.copyItem(at: fixture, to: url)

        do {
            let context = try ModelContext(ModelConfiguration.createMainContainer(at: url))
            let spaces = try context.fetch(FetchDescriptor<TabContainer>())
            #expect(spaces.map(\.name) == ["Work"])
            let tabs = try context.fetch(FetchDescriptor<Tab>(sortBy: [SortDescriptor(\.order)]))
            #expect(tabs.map(\.title) == ["Page A", "Page B", "Other"])
            #expect(tabs.map(\.type) == [.pinned, .normal, .fav])
            #expect(tabs.allSatisfy { $0.customName == nil && $0.parentContainer?.name == "Work" })
            #expect(tabs.map(\.displayName) == ["Page A", "Page B", "Other"])
            let folder = try #require(context.fetch(FetchDescriptor<Folder>()).first)
            #expect(folder.name == "Reading" && tabs.first?.folderID == folder.id)
            #expect(try context.fetch(FetchDescriptor<TabGroup>()).map(\.tabIDs) == [[tabs[1].id]])
            #expect(try context.fetch(FetchDescriptor<History>()).map(\.visitCount) == [2])
            #expect(try context.fetch(FetchDescriptor<SpaceTask>()).map(\.title) == ["Task"])
            tabs[1].customName = "My board"
            try context.save()
        }

        let reopened = try ModelContext(ModelConfiguration.createMainContainer(at: url))
        let tabs = try reopened.fetch(FetchDescriptor<Tab>(sortBy: [SortDescriptor(\.order)]))
        #expect(tabs.map(\.customName) == [nil, "My board", nil])
        #expect(tabs[1].displayName == "My board")
    }

    /// Opened twice at the new version: no migration the second time.
    @Test func aNewDatabaseOpensAgain() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try ModelConfiguration.createMainContainer(at: url)
        _ = try ModelConfiguration.createMainContainer(at: url)
    }
}
