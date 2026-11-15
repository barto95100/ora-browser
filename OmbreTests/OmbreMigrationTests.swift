import Foundation
@testable import Ombre
import SwiftData
import Testing

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
            let space = TabContainer(name: "Work")
            context.insert(space)
            let folder = Folder(name: "Reading", isOpened: true, container: space)
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

    /// Opened twice at the new version: no migration the second time.
    @Test func aNewDatabaseOpensAgain() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try ModelConfiguration.createMainContainer(at: url)
        _ = try ModelConfiguration.createMainContainer(at: url)
    }
}
