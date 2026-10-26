import AppKit

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
            if resolved.isStale {
                fileBookmark = Self.bookmark(for: resolved.url)
                try? modelContext?.save()
            }
            // The file was moved or renamed: follow it.
            if resolved.url.standardizedFileURL != file.standardizedFileURL {
                if type != .normal { savedURL = resolved.url }
                updateURL(resolved.url)
                try? modelContext?.save()
            }
            return
        }

        // Opened during this session: the sandbox grants access right now.
        // Saved at once: nothing else may save the tab before Ora quits.
        fileBookmark = Self.bookmark(for: file)
        try? modelContext?.save()
    }

    /// Gives the access back when the tab's page goes away.
    func endFileAccess() {
        fileAccessURL?.stopAccessingSecurityScopedResource()
        fileAccessURL = nil
    }

    // MARK: - Folder access

    /// After a local page loads: when it uses other local files (images,
    /// styles, scripts) that the sandbox blocks, offers to allow its folder.
    func offerFolderAccessIfNeeded() {
        guard url.isFileURL, LocalFolderAccess.shared.folder(containing: url) == nil else { return }
        let folder = url.deletingLastPathComponent()
        evaluateJavaScript(Self.localResourceCountScript) { [weak self] result, _ in
            guard let self, (result as? Int ?? 0) > 0 else { return }
            DispatchQueue.main.async { self.folderAccessRequest = folder }
        }
    }

    /// Asks the user to select the folder (the open panel grants the access),
    /// then reloads the page with it.
    func requestFolderAccess() {
        guard let folder = folderAccessRequest else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow Access"
        panel.message = "Allow Ora to read “\(folder.lastPathComponent)” so this page can show its images and styles."

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let selected = panel.url else { return }
            LocalFolderAccess.shared.grant(selected, persist: !isPrivate)
            folderAccessRequest = nil
            browserPage?.load(URLRequest(url: url))
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Number of local files the page uses besides itself.
    private static let localResourceCountScript = """
    (() => {
        const page = location.href.split('#')[0];
        const selector = 'img[src], link[href], script[src], source[src], video[src], audio[src], iframe[src]';
        return [...document.querySelectorAll(selector)]
            .map(element => element.src || element.href || '')
            .filter(url => url.startsWith('file:') && url.split('#')[0] !== page)
            .length;
    })()
    """

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
