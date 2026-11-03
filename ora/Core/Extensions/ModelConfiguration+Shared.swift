import Foundation
import SwiftData

extension ModelConfiguration {
    /// Where the main database lives.
    static var mainDatabaseURL: URL {
        OmbreDataFolder.applicationSupport.appending(path: "OmbreData.sqlite")
    }

    /// The models stored in the main database.
    static let mainSchema = Schema(versionedSchema: OmbreSchemaV1.self)

    /// The main database's configuration, stored at `url`.
    static func mainDatabase(at url: URL) -> ModelConfiguration {
        ModelConfiguration("OmbreData", schema: mainSchema, url: url)
    }

    /// Creates a ModelContainer for the main database stored at `url`.
    static func createMainContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: mainSchema,
            migrationPlan: OmbreMigrationPlan.self,
            configurations: mainDatabase(at: url)
        )
    }

    /// Creates a ModelContainer for the main models, kept in memory only.
    static func createInMemoryMainContainer() throws -> ModelContainer {
        try ModelContainer(
            for: mainSchema,
            migrationPlan: OmbreMigrationPlan.self,
            configurations: ModelConfiguration(schema: mainSchema, isStoredInMemoryOnly: true)
        )
    }
}
