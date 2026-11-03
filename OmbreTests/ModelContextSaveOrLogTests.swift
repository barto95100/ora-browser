import Foundation
@testable import Ombre
import SwiftData
import Testing

@MainActor
struct ModelContextSaveOrLogTests {
    private struct SaveFailure: Error {}

    @Test func successfulSaveWritesTheChanges() throws {
        let container = try ModelContainer(
            for: Download.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try context.insert(Download(
            originalURL: #require(URL(string: "https://example.com/a.zip")),
            fileName: "a.zip",
            fileSize: 1000
        ))

        #expect(context.saveOrLog("test save"))
        #expect(!context.hasChanges)

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Download>()) == 1)
    }

    @Test func failedSaveIsLoggedWithoutCrashing() {
        let succeeded = SaveOrLog.perform("test failure") { throw SaveFailure() }
        #expect(!succeeded)
    }

    @Test func performRunsTheSaveOnce() {
        var calls = 0
        #expect(SaveOrLog.perform("test count") { calls += 1 })
        #expect(calls == 1)
    }
}
