import Foundation

/// The installed extensions, in `Application Support/Ombre/Extensions/extensions.json`.
struct ExtensionRegistry {
    let fileURL: URL

    static let standard = ExtensionRegistry(
        fileURL: OmbreDataFolder.applicationSupport
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("extensions.json")
    )

    /// The records, only when the file was read and decoded as it is; nil
    /// otherwise (missing, unreadable): nothing is then known installed.
    func read() -> [ExtensionRecord]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ExtensionRecord].self, from: data)
    }

    func load() -> [ExtensionRecord] {
        if let records = read() { return records }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        // Unreadable: kept aside rather than overwritten by the next save.
        let aside = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        return []
    }

    func save(_ records: [ExtensionRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
