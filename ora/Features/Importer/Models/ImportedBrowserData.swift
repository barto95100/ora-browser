import Foundation

/// What another browser holds, read before anything is written to Ora: spaces
/// with their favorites (Zen's Essentials, Arc's favorites), and their pinned
/// tabs and folders, folders inside folders included.
struct ImportedBrowserData: Equatable {
    var spaces: [ImportedSpace]

    var favoriteCount: Int {
        spaces.reduce(0) { $0 + $1.favorites.count }
    }

    var pinnedTabCount: Int {
        spaces.reduce(0) { $0 + ImportedPinnedItem.tabCount(in: $1.pinned) }
    }

    var folderCount: Int {
        spaces.reduce(0) { $0 + ImportedPinnedItem.folderCount(in: $1.pinned) }
    }

    var isEmpty: Bool {
        spaces.allSatisfy { $0.favorites.isEmpty && $0.pinned.isEmpty }
    }
}

struct ImportedSpace: Equatable {
    var name: String
    /// An emoji, if the browser has one for it.
    var emoji: String?
    var favorites: [ImportedTab] = []
    /// In display order.
    var pinned: [ImportedPinnedItem] = []
}

struct ImportedTab: Equatable {
    var url: URL
    var title: String
    var faviconURL: URL?
}

indirect enum ImportedPinnedItem: Equatable {
    case tab(ImportedTab)
    case folder(name: String, isOpen: Bool, items: [ImportedPinnedItem])

    static func tabCount(in items: [ImportedPinnedItem]) -> Int {
        items.reduce(0) { count, item in
            switch item {
            case .tab: count + 1
            case let .folder(_, _, items): count + tabCount(in: items)
            }
        }
    }

    static func folderCount(in items: [ImportedPinnedItem]) -> Int {
        items.reduce(0) { count, item in
            switch item {
            case .tab: count
            case let .folder(_, _, items): count + 1 + folderCount(in: items)
            }
        }
    }
}
