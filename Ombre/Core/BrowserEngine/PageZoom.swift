import Foundation

/// The page's zoom (⌘+, ⌘-, ⌘0), in Safari's steps.
enum PageZoom {
    static let levels: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The next level in the direction of `step` (1 in, -1 out), or 1 for 0.
    static func level(after current: Double, step: Int) -> Double {
        if step > 0 { return levels.first { $0 > current + 0.001 } ?? levels.last ?? current }
        if step < 0 { return levels.last { $0 < current - 0.001 } ?? levels.first ?? current }
        return 1
    }
}
