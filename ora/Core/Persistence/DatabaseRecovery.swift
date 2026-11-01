import AppKit
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "DatabaseRecovery")

/// Opens the main database without ever crashing on the user's data: when it
/// can't be opened (corrupt file, schema SwiftData can't migrate on its own),
/// it is moved aside next to itself, never deleted, and a fresh one is
/// created. As a last resort the window works from memory for this session.
enum DatabaseRecovery {
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

    /// `OraData.corrupt-2026-11-01-153012.sqlite` in the database's folder,
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
            return try (ModelConfiguration.createOraContainer(at: storeURL), .opened)
        } catch {
            logger.error("Database failed to open: \(String(describing: error), privacy: .public)")
        }

        var backup: URL?
        if mayMoveAside, FileManager.default.fileExists(atPath: storeURL.path) {
            do {
                let moved = try moveStoreAside(at: storeURL, date: date)
                backup = moved
                let container = try ModelConfiguration.createOraContainer(at: storeURL)
                return (container, .recovered(backup: moved))
            } catch {
                logger.error("Fresh database failed to open: \(String(describing: error), privacy: .public)")
            }
        }
        return (inMemoryContainer(), .inMemory(backup: backup))
    }

    nonisolated static func inMemoryContainer() -> ModelContainer {
        do {
            return try ModelConfiguration.createInMemoryOraContainer()
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

    /// The main database's container, for a regular window.
    @MainActor static func openMainContainer() -> ModelContainer {
        let result = openContainer(at: ModelConfiguration.oraDatabaseURL, mayMoveAside: !hasMovedAside)
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
            alert.messageText = "Your tabs couldn't be restored"
            alert.informativeText = """
            Your browsing data couldn't be opened, so Ora started with fresh data. \
            A copy of the old data was kept: \(url.lastPathComponent).
            """
        case let .inMemory(url):
            backup = url
            alert.messageText = "Your tabs won't be saved"
            var text = "Your browsing data couldn't be opened. Tabs, history and downloads from this "
                + "session will be lost when Ora quits."
            if let url {
                text += " A copy of the old data was kept: \(url.lastPathComponent)."
            }
            alert.informativeText = text
        }
        alert.addButton(withTitle: "OK")
        if backup != nil {
            alert.addButton(withTitle: "Show in Finder")
        }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn, let backup else { return }
            NSWorkspace.shared.activateFileViewerSelecting([backup])
        }
    }
}
