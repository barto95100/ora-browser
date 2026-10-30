import Foundation

/// The installed extensions, in `Application Support/Extensions/extensions.json`.
struct ExtensionRegistry {
    let fileURL: URL

    static let standard = ExtensionRegistry(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("extensions.json")
    )

    func load() -> [ExtensionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([ExtensionRecord].self, from: data) { return records }
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
