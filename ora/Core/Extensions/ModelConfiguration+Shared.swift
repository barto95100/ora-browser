import Foundation
import SwiftData

extension ModelConfiguration {
    /// Where the main Ora database lives.
    static let oraDatabaseURL = URL.applicationSupportDirectory.appending(path: "Ora/OraData.sqlite")

    /// The models stored in the main Ora database.
    static let oraSchema = Schema([TabContainer.self, History.self, Download.self])

    /// Shared model configuration for the main Ora database
    static func oraDatabase(isPrivate: Bool = false) -> ModelConfiguration {
        if isPrivate {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            return oraDatabase(at: oraDatabaseURL)
        }
    }

    /// The main database's configuration, stored at `url`.
    static func oraDatabase(at url: URL) -> ModelConfiguration {
        ModelConfiguration("OraData", schema: oraSchema, url: url)
    }

    /// Creates a ModelContainer using the standard Ora database configuration
    static func createOraContainer(isPrivate: Bool = false) throws -> ModelContainer {
        return try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: oraDatabase(isPrivate: isPrivate)
        )
    }

    /// Creates a ModelContainer for the main database stored at `url`.
    static func createOraContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: oraSchema, configurations: oraDatabase(at: url))
    }

    /// Creates a ModelContainer for the main models, kept in memory only.
    static func createInMemoryOraContainer() throws -> ModelContainer {
        try ModelContainer(for: oraSchema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
