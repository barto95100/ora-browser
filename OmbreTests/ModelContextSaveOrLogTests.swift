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

    /// Deleting (the browsing time's purge…) no longer swallows a failure.
    @Test func deleteOrLogDeletesTheMatchingModels() throws {
        let container = try ModelContainer(
            for: Download.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for name in ["a.zip", "b.zip"] {
            try context.insert(Download(
                originalURL: #require(URL(string: "https://example.com/\(name)")),
                fileName: name
            ))
        }
        try context.save()

        #expect(context.deleteOrLog(Download.self, where: #Predicate { $0.fileName == "a.zip" }, "test delete"))
        context.saveOrLog("test save")

        #expect(try context.fetch(FetchDescriptor<Download>()).map(\.fileName) == ["b.zip"])
    }

    @Test func failedDeleteIsLoggedWithoutCrashing() {
        #expect(!SaveOrLog.perform("test failure", operation: "Delete") { throw SaveFailure() })
    }
}
