import Foundation

/// Split View, like Arc: two normal tabs of a space shown side by side. A pair
/// is stored on its left tab (`Tab.splitRightTabID`); the sidebar shows the
/// pair as one row and hides the right tab.
enum TabSplits {
    /// Narrowest share of the width a side can be given.
    static let minimumFraction = 0.2

    /// A tab and the tab it shows at its right, if any.
    struct Entry: Equatable {
        let id: UUID
        let rightID: UUID?
    }

    /// Valid pairs, left tab → right tab: both tabs are among `entries` (a
    /// space's normal tabs) and a tab is in one pair at most.
    static func pairs(_ entries: [Entry]) -> [UUID: UUID] {
        let ids = Set(entries.map(\.id))
        var paired = Set<UUID>()
        var result: [UUID: UUID] = [:]
        for entry in entries {
            guard let rightID = entry.rightID,
                  rightID != entry.id,
                  ids.contains(rightID),
                  !paired.contains(entry.id),
                  !paired.contains(rightID)
            else { continue }
            result[entry.id] = rightID
            paired.insert(entry.id)
            paired.insert(rightID)
        }
        return result
    }

    /// The tab shown beside `id`, from either side of its pair.
    static func partner(of id: UUID, in pairs: [UUID: UUID]) -> UUID? {
        if let rightID = pairs[id] { return rightID }
        return pairs.first { $0.value == id }?.key
    }

    /// The left side's share of the width, kept so both sides stay usable.
    static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, minimumFraction), 1 - minimumFraction)
    }
}
