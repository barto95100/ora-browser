import Foundation

/// Folders the user allowed Ora to read, so a local page can load the images,
/// styles and scripts next to it. The sandbox only grants the file that was
/// opened: access to its folder must come from the user (open panel). It is
/// kept as security-scoped bookmarks, so it survives relaunches.
final class LocalFolderAccess: @unchecked Sendable {
    static let shared = LocalFolderAccess()

    private static let defaultsKey = "LocalFolderAccessBookmarks"
    private let defaults: UserDefaults
    private let lock = NSLock()
    /// Granted folders, accessed for the app's lifetime.
    private var folders: [URL] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let bookmarks = defaults.array(forKey: Self.defaultsKey) as? [Data] ?? []
        var kept: [Data] = []
        for bookmark in bookmarks {
            var isStale = false
            guard let folder = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), folder.startAccessingSecurityScopedResource() else { continue }
            folders.append(folder)
            kept.append(isStale ? (Self.bookmark(for: folder) ?? bookmark) : bookmark)
        }
        if kept != bookmarks { defaults.set(kept, forKey: Self.defaultsKey) }
    }

    /// The granted folder a local page may read from: the closest one
    /// containing it, nil when none does.
    func folder(containing file: URL) -> URL? {
        lock.withLock { Self.closestFolder(containing: file, in: folders) }
    }

    /// Records a folder the user just selected in an open panel (which granted
    /// access for this session). Private windows keep it for the session only.
    func grant(_ folder: URL, persist: Bool) {
        let isNew = lock.withLock {
            guard !folders.contains(where: { $0.standardizedFileURL == folder.standardizedFileURL }) else {
                return false
            }
            folders.append(folder)
            return true
        }
        guard isNew else { return }
        _ = folder.startAccessingSecurityScopedResource()
        guard persist, let bookmark = Self.bookmark(for: folder) else { return }
        let bookmarks = defaults.array(forKey: Self.defaultsKey) as? [Data] ?? []
        defaults.set(bookmarks + [bookmark], forKey: Self.defaultsKey)
    }

    static func closestFolder(containing file: URL, in folders: [URL]) -> URL? {
        let filePath = file.standardizedFileURL.pathComponents
        return folders
            .filter { folder in
                let folderPath = folder.standardizedFileURL.pathComponents
                return folderPath.count < filePath.count && Array(filePath.prefix(folderPath.count)) == folderPath
            }
            .max { $0.standardizedFileURL.pathComponents.count < $1.standardizedFileURL.pathComponents.count }
    }

    private static func bookmark(for folder: URL) -> Data? {
        try? folder.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
