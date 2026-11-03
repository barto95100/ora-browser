import Foundation

/// Where Ombre keeps its files: everything under one `Ombre` folder, in
/// Application Support for the data and in Caches for what can be rebuilt.
enum OmbreDataFolder {
    /// `Application Support/Ombre`, created if needed.
    static var applicationSupport: URL {
        folder(in: .applicationSupportDirectory)
    }

    /// `Caches/Ombre`, created if needed.
    static var caches: URL {
        folder(in: .cachesDirectory)
    }

    /// A folder inside `parent`, created if needed.
    static func subfolder(_ name: String, of parent: URL) -> URL {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func folder(in directory: URL) -> URL {
        subfolder("Ombre", of: directory)
    }
}
