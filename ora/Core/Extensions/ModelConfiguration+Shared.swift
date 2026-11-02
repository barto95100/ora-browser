import Foundation
import SwiftData

extension ModelConfiguration {
    /// Where the main Ora database lives.
    static let oraDatabaseURL = URL.applicationSupportDirectory.appending(path: "Ora/OraData.sqlite")

    /// The models stored in the main Ora database.
    static let oraSchema = Schema([TabContainer.self, History.self, Download.self])

    /// The main database's configuration, stored at `url`.
    static func oraDatabase(at url: URL) -> ModelConfiguration {
        ModelConfiguration("OraData", schema: oraSchema, url: url)
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
