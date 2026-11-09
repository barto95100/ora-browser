import AppKit
import Foundation
import os
import SwiftData

private let logger = Logger(category: "DatabaseRecovery")

/// Opens the main database without ever crashing on the user's data: when it
/// can't be opened (corrupt file, schema SwiftData can't migrate on its own),
/// it is moved aside next to itself, never deleted, and a fresh one is
/// created. As a last resort the window works from memory for this session.
enum DatabaseRecovery {
    /// The error's kind in public; its description (the database's path,
    /// so the account's name) private.
    private static func log(_ what: String, _ error: Error) {
        let nsError = error as NSError
        let kind = "\(what): \(nsError.domain) \(nsError.code)"
        logger.error("\(kind, privacy: .public) \(String(describing: error), privacy: .private)")
    }

    enum Outcome: Equatable {
        /// The database opened normally.
        case opened
        /// The database was moved aside to `backup` and an empty one created.
        case recovered(backup: URL)
        /// Nothing could be opened on disk: the data lives in memory only.
        case inMemory(backup: URL?)
    }

    // MARK: - Moving the database aside

    /// SQLite's companion files, next to the database.
    nonisolated static let companionSuffixes = ["-wal", "-shm"]

    /// `OmbreData.corrupt-2026-11-01-153012.sqlite` in the database's folder,
    /// with `-2`, `-3`… added when that name is taken.
    nonisolated static func backupURL(
        for storeURL: URL,
        date: Date,
        fileManager: FileManager = .default
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = storeURL.deletingLastPathComponent()
        let name = storeURL.deletingPathExtension().lastPathComponent
        let ext = storeURL.pathExtension
        let stamp = "\(name).corrupt-\(formatter.string(from: date))"

        var candidate = folder.appending(path: "\(stamp).\(ext)")
        var index = 2
        while isTaken(candidate, fileManager: fileManager) {
            candidate = folder.appending(path: "\(stamp)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    /// Renames the database and its `-wal`/`-shm` files (when present) to the
    /// backup name, keeping SQLite's naming so the copy can still be opened.
    /// Returns the backup's URL.
    @discardableResult
    nonisolated static func moveStoreAside(
        at storeURL: URL,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let backup = backupURL(for: storeURL, date: date, fileManager: fileManager)
        try fileManager.moveItem(at: storeURL, to: backup)
        for suffix in companionSuffixes {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: backup.path + suffix))
        }
        return backup
    }

    private nonisolated static func isTaken(_ url: URL, fileManager: FileManager) -> Bool {
        ([""] + companionSuffixes).contains { fileManager.fileExists(atPath: url.path + $0) }
    }

    // MARK: - Opening

    /// Opens the database at `storeURL`. On failure, moves it aside (when
    /// `mayMoveAside`) and opens a fresh one; if that fails too, falls back
    /// to memory.
    nonisolated static func openContainer(
        at storeURL: URL,
        mayMoveAside: Bool = true,
        date: Date = Date()
    ) -> (container: ModelContainer, outcome: Outcome) {
        do {
            return try (ModelConfiguration.createMainContainer(at: storeURL), .opened)
        } catch {
            log("Database failed to open", error) // not shown
        }

        var backup: URL?
        if mayMoveAside, FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                let moved = try moveStoreAside(at: storeURL, date: date)
                backup = moved
                let container = try ModelConfiguration.createMainContainer(at: storeURL)
                return (container, .recovered(backup: moved))
            } catch {
                Self.log("Fresh database failed to open", error) // not shown
            }
        }
        return (inMemoryContainer(), .inMemory(backup: backup))
    }

    nonisolated static func inMemoryContainer() -> ModelContainer {
        do {
            return try ModelConfiguration.createInMemoryMainContainer()
        } catch {
            // Not a problem with the user's data: the schema itself is invalid,
            // which the tests catch.
            preconditionFailure("Invalid SwiftData schema, even in memory: \(error)")
        }
    }

    // MARK: - Main database, once per launch

    /// Whether the main database was already moved aside during this launch:
    /// later windows never move the fresh one aside again.
    @MainActor private static var hasMovedAside = false
    /// What the first window tells the user, once.
    @MainActor private static var pendingNotice: Outcome?

    /// The app's one container on the main database: normal windows, the
    /// settings and passwords windows all use it. Opened on first use.
    @MainActor static var mainContainer: ModelContainer {
        if let openedMainContainer { return openedMainContainer }
        // The tests never open the user's database.
        let container = TestHost.isActive ? inMemoryContainer() : openMainContainer()
        openedMainContainer = container
        return container
    }

    @MainActor private static var openedMainContainer: ModelContainer?
    /// Whether the database on disk was opened, for the tests.
    @MainActor private(set) static var hasOpenedDatabaseOnDisk = false

    /// Opens the main database's container (see `mainContainer`).
    @MainActor private static func openMainContainer() -> ModelContainer {
        hasOpenedDatabaseOnDisk = true
        let result = openContainer(at: ModelConfiguration.mainDatabaseURL, mayMoveAside: !hasMovedAside)
        switch result.outcome {
        case .opened:
            break
        case .recovered:
            hasMovedAside = true
            pendingNotice = result.outcome
        case let .inMemory(backup):
            if backup != nil { hasMovedAside = true }
            // A window already warned about the move keeps that warning.
            if pendingNotice == nil || backup != nil { pendingNotice = result.outcome }
        }
        return result.container
    }

    /// The notice to show, once: the next calls return nil.
    @MainActor static func takePendingNotice() -> Outcome? {
        defer { pendingNotice = nil }
        return pendingNotice
    }

    // MARK: - Alert

    @MainActor static func presentNotice(_ outcome: Outcome, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        var backup: URL?
        switch outcome {
        case .opened:
            return
        case let .recovered(url):
            backup = url
            alert.messageText = String(localized: "Your tabs couldn't be restored")
            alert.informativeText = """
            Your browsing data couldn't be opened, so Ombre started with fresh data. \
            A copy of the old data was kept: \(url.lastPathComponent).
            """
        case let .inMemory(url):
            backup = url
            alert.messageText = String(localized: "Your tabs won't be saved")
            var text = String(
                // swiftlint:disable:next line_length
                localized: "Your browsing data couldn't be opened. Tabs, history and downloads from this session will be lost when Ombre quits."
            )
            if let url {
                text += " " + String(localized: "A copy of the old data was kept: \(url.lastPathComponent).")
            }
            alert.informativeText = text
        }
        alert.addButton(withTitle: String(localized: "OK"))
        if backup != nil {
            alert.addButton(withTitle: String(localized: "Show in Finder"))
        }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn, let backup else { return }
            NSWorkspace.shared.activateFileViewerSelecting([backup])
        }
    }
}
