import AppKit
import Foundation

/// A note: a Markdown file of its space's folder.
struct Note: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date

    var id: URL {
        url
    }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// Notes are Markdown files, one folder per space, named after it, in Ora's
/// Application Support folder (in its sandbox container), so they can be
/// opened from the Finder or another editor:
/// `Notes/<Space name>/<Note title>.md`.
final class NotesStore {
    static let shared = NotesStore()

    private let fileManager = FileManager.default
    /// Space id → folder name: the folder follows a renamed space.
    private var folderNames: [String: String]

    private init() {
        folderNames = [:]
        folderNames = loadFolderNames()
    }

    var rootFolder: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Notes", isDirectory: true)
    }

    /// The space's folder, created if needed, renamed if the space was.
    func folder(for spaceID: UUID, named spaceName: String) -> URL {
        let wanted = Self.fileName(from: spaceName, fallback: "Space")
        var current = folderNames[spaceID.uuidString]
        if current.map({ !Self.isFolderName($0, for: wanted) }) ?? true {
            let target = uniqueURL(in: rootFolder, base: wanted, pathExtension: nil)
            if let current, fileManager.fileExists(atPath: rootFolder.appendingPathComponent(current).path) {
                try? fileManager.moveItem(at: rootFolder.appendingPathComponent(current), to: target)
            }
            current = target.lastPathComponent
            folderNames[spaceID.uuidString] = current
            saveFolderNames()
        }
        let folder = rootFolder.appendingPathComponent(current ?? wanted, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The folder's notes, most recently changed first.
    func notes(in folder: URL) -> [Note] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return Note(url: url, modifiedAt: date)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func create(in folder: URL, title: String = "Untitled") -> Note? {
        let url = uniqueURL(in: folder, base: Self.fileName(from: title, fallback: "Untitled"), pathExtension: "md")
        guard fileManager.createFile(atPath: url.path, contents: Data()) else { return nil }
        return Note(url: url, modifiedAt: Date())
    }

    func read(_ note: Note) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    func write(_ text: String, to note: Note) {
        try? text.write(to: note.url, atomically: true, encoding: .utf8)
    }

    /// Renames the note's file; returns the renamed note (or the same one).
    func rename(_ note: Note, to title: String) -> Note {
        let base = Self.fileName(from: title, fallback: note.title)
        guard base != note.title else { return note }
        let url = uniqueURL(in: note.url.deletingLastPathComponent(), base: base, pathExtension: "md")
        guard (try? fileManager.moveItem(at: note.url, to: url)) != nil else { return note }
        renameTabNote(
            from: note.url.lastPathComponent,
            to: url.lastPathComponent,
            in: note.url.deletingLastPathComponent()
        )
        return Note(url: url, modifiedAt: Date())
    }

    /// Moves the note to the Trash, so it can be put back.
    func delete(_ note: Note) {
        try? fileManager.trashItem(at: note.url, resultingItemURL: nil)
    }

    // MARK: - Tab notes

    /// The note of a tab (pinned, favorite or not), if it has one.
    func tabNote(for tabID: UUID, in folder: URL) -> Note? {
        guard let name = tabNoteNames(in: folder)[tabID.uuidString] else { return nil }
        let url = folder.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Note(url: url, modifiedAt: date ?? Date())
    }

    /// A new note for the tab, named after its page, starting with its link.
    func createTabNote(for tabID: UUID, title: String, pageURL: URL, in folder: URL) -> Note? {
        guard let note = create(in: folder, title: title) else { return nil }
        let link = "[\(title.replacingOccurrences(of: "]", with: ""))](\(pageURL.absoluteString))"
        write(link + "\n\n", to: note)
        var names = tabNoteNames(in: folder)
        names[tabID.uuidString] = note.url.lastPathComponent
        saveTabNoteNames(names, in: folder)
        return note
    }

    /// Saves a capture in the folder's `attachments`; returns its path for
    /// the note (`attachments/capture-….png`).
    func saveImage(_ png: Data, in folder: URL) -> String? {
        let attachments = folder.appendingPathComponent("attachments", isDirectory: true)
        try? fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = uniqueURL(in: attachments, base: "capture-" + formatter.string(from: Date()), pathExtension: "png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return nil }
        return "attachments/" + url.lastPathComponent
    }

    private func tabNotesFile(in folder: URL) -> URL {
        folder.appendingPathComponent(".tabs.json")
    }

    /// Tab id → note file name, per space folder.
    private func tabNoteNames(in folder: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: tabNotesFile(in: folder)),
              let names = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return names
    }

    private func saveTabNoteNames(_ names: [String: String], in folder: URL) {
        if let data = try? JSONEncoder().encode(names) {
            try? data.write(to: tabNotesFile(in: folder), options: .atomic)
        }
    }

    /// A renamed tab note keeps its tab.
    private func renameTabNote(from oldName: String, to newName: String, in folder: URL) {
        var names = tabNoteNames(in: folder)
        guard let tabID = names.first(where: { $0.value == oldName })?.key else { return }
        names[tabID] = newName
        saveTabNoteNames(names, in: folder)
    }

    func showInFinder(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Whether a folder name is the space's name, or that name numbered
    /// ("Work 2") because another space has it too.
    static func isFolderName(_ folderName: String, for base: String) -> Bool {
        if folderName == base { return true }
        guard folderName.hasPrefix(base + " ") else { return false }
        let suffix = folderName.dropFirst(base.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// A name usable as a file name: no slash or colon, not hidden.
    static func fileName(from title: String, fallback: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(120))
    }

    private func uniqueURL(in folder: URL, base: String, pathExtension: String?) -> URL {
        func url(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: pathExtension == nil)
            return pathExtension.map { url.appendingPathExtension($0) } ?? url
        }
        var candidate = url(base)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url("\(base) \(number)")
            number += 1
        }
        return candidate
    }

    private var folderNamesFile: URL {
        rootFolder.appendingPathComponent(".spaces.json")
    }

    private func loadFolderNames() -> [String: String] {
        guard let data = try? Data(contentsOf: folderNamesFile),
              let names = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return names
    }

    private func saveFolderNames() {
        try? fileManager.createDirectory(at: rootFolder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(folderNames) {
            try? data.write(to: folderNamesFile, options: .atomic)
        }
    }
}
