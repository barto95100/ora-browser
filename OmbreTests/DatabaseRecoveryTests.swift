import Foundation
@testable import Ombre
import SwiftData
import Testing

struct DatabaseRecoveryTests {
    /// A fresh folder per test, removed afterwards.
    private final class Folder {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "ombre-db-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        var store: URL {
            url.appending(path: "OmbreData.sqlite")
        }

        func write(_ text: String, to name: String) throws {
            try Data(text.utf8).write(to: url.appending(path: name))
        }

        func read(_ name: String) throws -> String {
            try String(contentsOf: url.appending(path: name), encoding: .utf8)
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: url.appending(path: name).path)
        }

        func names() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        }
    }

    /// 1 November 2026, 15:30:12 local time.
    private let date: Date = {
        let components = DateComponents(year: 2026, month: 11, day: 1, hour: 15, minute: 30, second: 12)
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }()

    private let backupName = "OmbreData.corrupt-2026-11-01-153012.sqlite"

    @Test func backupIsNamedWithTheDateInTheSameFolder() throws {
        let folder = try Folder()

        let backup = DatabaseRecovery.backupURL(for: folder.store, date: date)

        #expect(backup.lastPathComponent == backupName)
        #expect(backup.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL)
    }

    @Test func takenBackupNameGetsANumber() throws {
        let folder = try Folder()
        try folder.write("old", to: backupName)
        try folder.write("old", to: "OmbreData.corrupt-2026-11-01-153012-2.sqlite-wal")

        let backup = DatabaseRecovery.backupURL(for: folder.store, date: date)

        #expect(backup.lastPathComponent == "OmbreData.corrupt-2026-11-01-153012-3.sqlite")
    }

    @Test func storeAndCompanionFilesAreMovedAside() throws {
        let folder = try Folder()
        try folder.write("db", to: "OmbreData.sqlite")
        try folder.write("wal", to: "OmbreData.sqlite-wal")
        try folder.write("shm", to: "OmbreData.sqlite-shm")

        let backup = try DatabaseRecovery.moveStoreAside(at: folder.store, date: date)

        #expect(backup.lastPathComponent == backupName)
        #expect(try folder.names() == [backupName, backupName + "-shm", backupName + "-wal"])
        #expect(try folder.read(backupName) == "db")
        #expect(try folder.read(backupName + "-wal") == "wal")
        #expect(try folder.read(backupName + "-shm") == "shm")
    }

    @Test func missingCompanionFilesAreNotAnError() throws {
        let folder = try Folder()
        try folder.write("db", to: "OmbreData.sqlite")

        try DatabaseRecovery.moveStoreAside(at: folder.store, date: date)

        #expect(try folder.names() == [backupName])
    }

    @Test func corruptDatabaseIsKeptAndReplacedByAnEmptyOne() throws {
        let folder = try Folder()
        try folder.write("x\n", to: "OmbreData.sqlite")

        let result = DatabaseRecovery.openContainer(at: folder.store, date: date)

        #expect(result.outcome == .recovered(backup: folder.url.appending(path: backupName)))
        #expect(try folder.read(backupName) == "x\n")
        #expect(folder.exists("OmbreData.sqlite"))
        let context = ModelContext(result.container)
        #expect(try context.fetchCount(FetchDescriptor<TabContainer>()) == 0)
    }

    @Test func corruptDatabaseIsNotMovedTwice() throws {
        let folder = try Folder()
        try folder.write("x\n", to: "OmbreData.sqlite")

        let result = DatabaseRecovery.openContainer(at: folder.store, mayMoveAside: false, date: date)

        #expect(result.outcome == .inMemory(backup: nil))
        #expect(try folder.read("OmbreData.sqlite") == "x\n")
        #expect(!folder.exists(backupName))
    }

    @Test func healthyDatabaseOpensInPlace() throws {
        let folder = try Folder()
        do {
            let container = try ModelConfiguration.createMainContainer(at: folder.store)
            let context = ModelContext(container)
            context.insert(TabContainer(name: "Kept", emoji: "🧪"))
            try context.save()
        }

        let result = DatabaseRecovery.openContainer(at: folder.store, date: date)

        #expect(result.outcome == .opened)
        #expect(!folder.exists(backupName))
        let context = ModelContext(result.container)
        #expect(try context.fetchCount(FetchDescriptor<TabContainer>()) == 1)
    }

    @Test func schemaWorksInMemory() throws {
        let container = DatabaseRecovery.inMemoryContainer()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TabContainer>()) == 0)
    }
}
