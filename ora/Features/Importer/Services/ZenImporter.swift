import Foundation

/// Reads a Zen profile's session (`zen-sessions.jsonlz4`): its spaces, their
/// Essentials, and their pinned tabs and folders. Open tabs are left out.
enum ZenImporter {
    enum Failure: Error {
        case noSession
        case unreadable
    }

    static let sessionFileName = "zen-sessions.jsonlz4"

    /// Zen's profiles folder in the real home, not the app's container.
    static var profilesFolder: URL {
        RealHome.url.appendingPathComponent("Library/Application Support/zen/Profiles", isDirectory: true)
    }

    /// The session file in a profile folder, or nil if it has none.
    static func sessionFile(inProfile folder: URL) -> URL? {
        let file = folder.appendingPathComponent(sessionFileName)
        return FileManager.default.isReadableFile(atPath: file.path) ? file : nil
    }

    /// The profile to read in a chosen folder: the folder itself, or the most
    /// recently used profile in it (the Profiles folder, or Zen's own folder).
    static func profile(in folder: URL) -> URL? {
        if sessionFile(inProfile: folder) != nil { return folder }
        if let profile = profiles(in: folder).first { return profile }
        return profiles(in: folder.appendingPathComponent("Profiles", isDirectory: true)).first
    }

    /// Profiles that have a session, most recently used first.
    static func profiles(in parent: URL = profilesFolder) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: keys
        )) ?? []
        func modified(_ folder: URL) -> Date {
            guard let file = sessionFile(inProfile: folder) else { return .distantPast }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }
        return folders
            .filter { sessionFile(inProfile: $0) != nil }
            .sorted { modified($0) > modified($1) }
    }

    static func read(profile folder: URL) throws -> ImportedBrowserData {
        guard let file = sessionFile(inProfile: folder) else { throw Failure.noSession }
        return try read(sessionFile: file)
    }

    static func read(sessionFile file: URL) throws -> ImportedBrowserData {
        let data = try Data(contentsOf: file)
        return try parse(MozLZ4.decompress(data))
    }

    static func parse(_ json: Data) throws -> ImportedBrowserData {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw Failure.unreadable
        }
        return ZenSession(root).importedData()
    }
}

/// The real home folder: the app's own home is its sandbox container.
enum RealHome {
    static var url: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

/// The parts of a Zen session that the import uses.
private struct ZenSession {
    struct Space {
        let id: String
        let name: String
        let emoji: String?
        let userContextID: Int?
    }

    struct Folder {
        let id: String
        let name: String
        let parentID: String?
        let spaceID: String?
        let isOpen: Bool
        /// Zen keeps split views as folders; their tabs belong to the level above.
        let isSplitView: Bool
    }

    struct PinnedTab {
        let position: Int
        let tab: ImportedTab
        let isEssential: Bool
        let spaceID: String?
        let userContextID: Int?
        let folderID: String?
    }

    let spaces: [Space]
    let folders: [Folder]
    let tabs: [PinnedTab]

    init(_ root: [String: Any]) {
        spaces = (root["spaces"] as? [[String: Any]] ?? []).compactMap { space in
            guard let id = space["uuid"] as? String else { return nil }
            let name = (space["name"] as? String).flatMap(\.nonBlank) ?? "Space"
            let icon = (space["icon"] as? String).flatMap(\.nonBlank)
            return Space(
                id: id, name: name,
                emoji: icon.flatMap { $0.isEmoji ? $0 : nil },
                userContextID: space["containerTabId"] as? Int
            )
        }
        folders = (root["folders"] as? [[String: Any]] ?? []).compactMap { folder in
            guard let id = folder["id"] as? String else { return nil }
            return Folder(
                id: id,
                name: (folder["name"] as? String).flatMap(\.nonBlank) ?? "Folder",
                parentID: folder["parentId"] as? String,
                spaceID: folder["workspaceId"] as? String,
                isOpen: !(folder["collapsed"] as? Bool ?? false),
                isSplitView: folder["splitViewGroup"] as? Bool ?? false
            )
        }
        tabs = (root["tabs"] as? [[String: Any]] ?? []).enumerated().compactMap { position, tab in
            Self.pinnedTab(tab, position: position)
        }
    }

    private static func pinnedTab(_ tab: [String: Any], position: Int) -> PinnedTab? {
        guard tab["pinned"] as? Bool == true,
              tab["zenIsGlance"] as? Bool != true,
              tab["zenIsEmpty"] as? Bool != true
        else { return nil }

        // A pinned tab opens on the page it was pinned with, not where it was left.
        let initial = (tab["_zenPinnedInitialState"] as? [String: Any])?["entry"] as? [String: Any]
        let entries = tab["entries"] as? [[String: Any]] ?? []
        let index = min(max((tab["index"] as? Int ?? entries.count) - 1, 0), max(entries.count - 1, 0))
        let current = entries.indices.contains(index) ? entries[index] : nil
        guard let entry = initial ?? current,
              let url = (entry["url"] as? String).flatMap(URL.init(string:)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }

        let label = (tab["zenStaticLabel"] as? String).flatMap(\.nonBlank)
        let title = label ?? (entry["title"] as? String).flatMap(\.nonBlank) ?? url.host ?? url.absoluteString
        let favicon = (tab["image"] as? String).flatMap(URL.init(string:)).flatMap { icon in
            ["http", "https"].contains(icon.scheme?.lowercased() ?? "") ? icon : nil
        }
        return PinnedTab(
            position: position,
            tab: ImportedTab(url: url, title: title, faviconURL: favicon),
            isEssential: tab["zenEssential"] as? Bool ?? false,
            spaceID: tab["zenWorkspace"] as? String,
            userContextID: tab["userContextId"] as? Int,
            folderID: tab["groupId"] as? String
        )
    }

    func importedData() -> ImportedBrowserData {
        guard !spaces.isEmpty else { return ImportedBrowserData(spaces: []) }
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Essentials go with the space of their container, as Zen shows them.
        func spaceOfEssential(_ tab: PinnedTab) -> String {
            if let context = tab.userContextID,
               let space = spaces.first(where: { $0.userContextID == context }) { return space.id }
            if let id = tab.spaceID, spaces.contains(where: { $0.id == id }) { return id }
            return spaces[0].id
        }

        // The folder a tab or folder shows in, skipping split views.
        func visibleFolder(_ id: String?) -> String? {
            var current = id
            var seen = Set<String>()
            while let id = current, let folder = foldersByID[id], seen.insert(id).inserted {
                if !folder.isSplitView { return id }
                current = folder.parentID
            }
            return nil
        }

        return ImportedBrowserData(spaces: spaces.map { space in
            let favorites = tabs
                .filter { $0.isEssential && spaceOfEssential($0) == space.id }
                .map(\.tab)
            let pinned = tabs.filter { !$0.isEssential && ($0.spaceID ?? spaces[0].id) == space.id }
            let spaceFolders = folders.filter { !$0.isSplitView && ($0.spaceID ?? spaces[0].id) == space.id }
            return ImportedSpace(
                name: space.name,
                emoji: space.emoji,
                favorites: favorites,
                pinned: items(
                    in: nil,
                    tabs: pinned.map { ($0, visibleFolder($0.folderID)) },
                    folders: spaceFolders.map { ($0, visibleFolder($0.parentID)) },
                    depth: 0
                ).map(\.item)
            )
        })
    }

    /// The items at one level, ordered as in Zen: by where their first tab sits
    /// in the session, empty folders last.
    private func items(
        in folderID: String?,
        tabs: [(tab: PinnedTab, folder: String?)],
        folders: [(folder: Folder, parent: String?)],
        depth: Int
    ) -> [(position: Int, item: ImportedPinnedItem)] {
        guard depth < 32 else { return [] }
        let tabItems: [(position: Int, item: ImportedPinnedItem)] = tabs
            .filter { $0.folder == folderID }
            .map { (position: $0.tab.position, item: .tab($0.tab.tab)) }
        let folderItems: [(position: Int, item: ImportedPinnedItem)] = folders
            .filter { $0.parent == folderID }
            .map { entry in
                let children = items(in: entry.folder.id, tabs: tabs, folders: folders, depth: depth + 1)
                let folder = ImportedPinnedItem.folder(
                    name: entry.folder.name, isOpen: entry.folder.isOpen, items: children.map(\.item)
                )
                return (position: children.map(\.position).min() ?? Int.max, item: folder)
            }
        // A stable sort keeps empty folders in Zen's folder order.
        return (tabItems + folderItems).enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element)
    }
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Zen's icon is an emoji, or a path to one of its own SVG icons.
    var isEmoji: Bool {
        count == 1 && unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x7F }
    }
}
