import Foundation

/// Reads Arc's sidebar file (`StorableSidebar.json`, in Arc's support folder):
/// its spaces with their pinned tabs and folders, and the favorites (Arc's
/// "top apps"). Only the local file is read, so it still works once Arc is
/// gone (its service closes on December 22, 2026). Open tabs are left out.
///
/// The file's lists alternate an id and its object: `["id1", {…}, "id2", {…}]`.
/// A space names its pinned container (`containerIDs: ["pinned", "<id>", …]`);
/// an item is a tab (`data.tab.savedURL`), a folder (`data.list`) or a split
/// view (`data.splitView`), with its children in `childrenIds`.
enum ArcImporter {
    enum Failure: Error, Equatable {
        case unreadable
        case nothingToImport
    }

    static let fileName = "StorableSidebar.json"

    /// Arc's support folder in the real home, not the app's container.
    static var supportFolder: URL {
        RealHome.url.appendingPathComponent("Library/Application Support/Arc", isDirectory: true) // not shown
    }

    /// Folders deeper than this are flattened into their parent (a forged
    /// file could nest without end).
    static let maxDepth = 16

    static let maxFileSize = 128 * 1024 * 1024

    static func read(file: URL) throws -> ImportedBrowserData {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileSize, let data = try? Data(contentsOf: file) else { throw Failure.unreadable }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> ImportedBrowserData {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]]
        else { throw Failure.unreadable }

        var items: [String: [String: Any]] = [:]
        var spaces: [[String: Any]] = []
        // Each profile's favorites container: `[{profile}, "id", {profile}, "id"…]`.
        var topApps: [(profile: String, id: String)] = []
        for container in containers {
            for case let item as [String: Any] in container["items"] as? [Any] ?? [] {
                if let id = item["id"] as? String { items[id] = item }
            }
            spaces += (container["spaces"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            let list = container["topAppsContainerIDs"] as? [Any] ?? []
            for (index, entry) in list.enumerated() {
                guard let id = entry as? String else { continue }
                topApps.append((profileKey(index > 0 ? list[index - 1] : nil), id))
            }
        }

        let reader = ItemReader(items: items)
        var imported: [ImportedSpace] = spaces.compactMap { space in
            guard let containerIDs = space["containerIDs"] as? [Any] else { return nil }
            let title = (space["title"] as? String).flatMap(\.nonBlank)
                ?? String(localized: "Space")
            var result = ImportedSpace(name: title, emoji: emoji(of: space))
            if let pinnedID = id(after: "pinned", in: containerIDs) {
                result.pinned = reader.children(of: pinnedID, depth: 0)
            }
            return result
        }

        // A profile's favorites are shared by its spaces: they go to its first
        // space (or the first space), each address once.
        let profiles = spaces.compactMap { space -> String? in
            space["containerIDs"] is [Any] ? profileKey(space["profile"]) : nil
        }
        for (profile, id) in topApps {
            let favorites = reader.tabs(in: id)
            guard !favorites.isEmpty else { continue }
            if imported.isEmpty { imported = [ImportedSpace(name: String(localized: "Space"))] }
            let target = profiles.firstIndex(of: profile) ?? 0
            for favorite in favorites where !imported[target].favorites.contains(where: { $0.url == favorite.url }) {
                imported[target].favorites.append(favorite)
            }
        }

        let data = ImportedBrowserData(spaces: imported)
        guard !data.spaces.isEmpty, !data.isEmpty else { throw Failure.nothingToImport }
        return data
    }

    /// A profile as Arc writes it (`{"default": true}`, or `{"custom": {…}}`), as a key.
    static func profileKey(_ value: Any?) -> String {
        guard let profile = value as? [String: Any], profile["default"] == nil,
              let custom = profile["custom"],
              let data = try? JSONSerialization.data(withJSONObject: custom, options: .sortedKeys)
        else { return "default" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The id following `label` in an alternating list (`["pinned", "<id>"]`).
    static func id(after label: String, in list: [Any]) -> String? {
        guard let index = list.firstIndex(where: { ($0 as? String) == label }), index + 1 < list.count else {
            return nil
        }
        return list[index + 1] as? String
    }

    /// A space's emoji (`customInfo.iconType.emoji_v2`, or the older
    /// `emoji`, a Unicode scalar's value).
    static func emoji(of space: [String: Any]) -> String? {
        let icon = (space["customInfo"] as? [String: Any])?["iconType"] as? [String: Any]
        if let emoji = (icon?["emoji_v2"] as? String).flatMap(\.nonBlank), emoji.isEmoji { return emoji }
        if let value = (icon?["emoji"] as? NSNumber)?.uint32Value, let scalar = Unicode.Scalar(value) {
            let emoji = String(Character(scalar))
            return emoji.isEmoji ? emoji : nil
        }
        return nil
    }
}

private final class ItemReader {
    let items: [String: [String: Any]]
    /// Every item is read once: a forged file can't repeat or loop through one.
    private var visited: Set<String> = []

    init(items: [String: [String: Any]]) {
        self.items = items
    }

    /// A container's or folder's items, in the sidebar's order.
    func children(of id: String, depth: Int) -> [ImportedPinnedItem] {
        // Past this, nothing more is read (folders deeper than `maxDepth` are flattened).
        guard depth <= ArcImporter.maxDepth * 4 else { return [] }
        visited.insert(id)
        let ids = (items[id]?["childrenIds"] as? [Any])?.compactMap { $0 as? String } ?? []
        return ids.flatMap { item(id: $0, depth: depth) }
    }

    /// The web tabs in a container (the favorites), folders' tabs included.
    func tabs(in id: String) -> [ImportedTab] {
        ImportedPinnedItem.tabs(in: children(of: id, depth: ArcImporter.maxDepth))
    }

    private func item(id: String, depth: Int) -> [ImportedPinnedItem] {
        guard visited.insert(id).inserted, let item = items[id], let data = item["data"] as? [String: Any] else {
            return []
        }
        if let tab = data["tab"] as? [String: Any] {
            return tabItem(tab, customTitle: item["title"] as? String).map { [.tab($0)] } ?? []
        }
        if data["list"] != nil {
            let children = children(of: id, depth: depth + 1)
            // Too deep: its content goes to the parent.
            guard depth < ArcImporter.maxDepth else { return children }
            let name = (item["title"] as? String).flatMap(\.nonBlank) ?? String(localized: "Folder")
            return [.folder(name: name, isOpen: false, items: children)]
        }
        // A split view: its tabs, side by side in the sidebar.
        if data["splitView"] != nil {
            return children(of: id, depth: depth + 1)
        }
        return []
    }

    private func tabItem(_ tab: [String: Any], customTitle: String?) -> ImportedTab? {
        guard let address = tab["savedURL"] as? String, let url = URL(string: address),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        let title = customTitle.flatMap(\.nonBlank)
            ?? (tab["savedTitle"] as? String).flatMap(\.nonBlank)
            ?? url.host ?? address
        return ImportedTab(url: url, title: title)
    }
}

private extension String {
    /// The text without its outer spaces, or nil when nothing is left.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One emoji (Ombre shows it as the space's icon).
    var isEmoji: Bool {
        count == 1 && unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x7F }
    }
}
