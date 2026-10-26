import Foundation

/// Local files stay readable after a relaunch. The sandbox only lets Ora read a
/// file the user opened during the current session, so the tab keeps a
/// security-scoped bookmark to it and uses it to get access back.
extension Tab {
    /// The local file the tab loads (pinned and favorite tabs load their saved URL).
    private var fileToLoad: URL? {
        let url = type != .normal ? (savedURL ?? url) : url
        return url.isFileURL ? url : nil
    }

    /// Called before the page loads: regains access to the tab's file from its
    /// bookmark, or bookmarks the file the user just opened.
    func beginFileAccessIfNeeded() {
        guard let file = fileToLoad, fileAccessURL == nil else { return }

        if let bookmark = fileBookmark, let resolved = Self.resolve(bookmark) {
            guard resolved.url.startAccessingSecurityScopedResource() else { return }
            fileAccessURL = resolved.url
            if resolved.isStale { fileBookmark = Self.bookmark(for: resolved.url) }
            // The file was moved or renamed: follow it.
            if resolved.url.standardizedFileURL != file.standardizedFileURL {
                if type != .normal { savedURL = resolved.url }
                updateURL(resolved.url)
            }
            return
        }

        // Opened during this session: the sandbox grants access right now.
        fileBookmark = Self.bookmark(for: file)
    }

    /// Gives the access back when the tab's page goes away.
    func endFileAccess() {
        fileAccessURL?.stopAccessingSecurityScopedResource()
        fileAccessURL = nil
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }
}
