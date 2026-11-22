import CoreGraphics

/// The favorites grid at a given width, like Arc's: as many columns as cells
/// of at least `minimumCellWidth` fit (at most `maximumColumns`), fewer
/// favorites filling the row; cells and icons growing and shrinking with the
/// width, within their limits.
struct FavoritesGridMetrics: Equatable {
    static let spacing: CGFloat = 10
    static let minimumCellWidth: CGFloat = 48
    static let maximumColumns = 6
    /// A cell's height: 48 pt at the narrowest sidebar's grid (180 pt), as
    /// before, growing with the width up to 56 pt, continuously (a new
    /// column never makes the rows jump).
    static let cellHeights: ClosedRange<CGFloat> = 44 ... 56
    static let baseWidth: CGFloat = 180
    static let baseHeight: CGFloat = 48
    /// Points of height per point of width.
    static let heightSlope: CGFloat = 8 / 360
    /// The icon, the same share of the cell's height at every size (20 pt in
    /// a 48 pt cell, as before).
    static let iconShare: CGFloat = 20 / 48
    static let iconSizes: ClosedRange<CGFloat> = 16 ... 23
    /// How far the badges (camera, microphone, sound, agent) sit out of the
    /// icon's corner, as a share of the icon (7 pt for a 20 pt icon).
    static let badgeOffsetShare: CGFloat = 7 / 20

    let columns: Int
    let rows: Int
    /// A cell's width before rounding (see `frame(at:)`).
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    /// `count` favorites (at least one cell) in `width`.
    init(width: CGFloat, count: Int) {
        let width = max(0, width)
        let spacing = Self.spacing
        let fitting = Int(((width + spacing) / (Self.minimumCellWidth + spacing)).rounded(.down))
        let rowCapacity = min(max(1, fitting), Self.maximumColumns)
        let count = max(1, count)
        columns = min(count, rowCapacity)
        rows = (count + columns - 1) / columns
        self.width = width
        cellWidth = Self.cellWidth(in: width, columns: columns)
        // From the width alone, not the columns: a lone favorite stretched
        // across the row is not taller. Whole points: rows on the pixel
        // grid, the icon sharp.
        let height = (Self.baseHeight + (width - Self.baseWidth) * Self.heightSlope).rounded(.down)
        cellHeight = min(max(height, Self.cellHeights.lowerBound), Self.cellHeights.upperBound)
    }

    /// The width the grid has.
    private let width: CGFloat

    private static func cellWidth(in width: CGFloat, columns: Int) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The whole grid's height.
    var height: CGFloat {
        CGFloat(rows) * cellHeight + CGFloat(rows - 1) * Self.spacing
    }

    /// Where the favorite at `index` goes, from the grid's top left corner:
    /// on whole points (the icon sharp), the cells sharing the leftover
    /// points so the row still ends at the grid's edge.
    func frame(at index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        let left = columnEdge(column)
        return CGRect(
            x: left,
            y: CGFloat(row) * (cellHeight + Self.spacing),
            width: max(0, columnEdge(column + 1) - Self.spacing - left),
            height: cellHeight
        )
    }

    /// Where column `column` starts (`columns`: past the grid, by a spacing).
    private func columnEdge(_ column: Int) -> CGFloat {
        (CGFloat(column) * (width + Self.spacing) / CGFloat(columns)).rounded(.down)
    }

    /// The icon's size in a cell `height` tall.
    static func iconSize(forCellHeight height: CGFloat) -> CGFloat {
        min(max((height * iconShare).rounded(), iconSizes.lowerBound), iconSizes.upperBound)
    }

    /// How far the badges sit out of an icon `size` wide.
    static func badgeOffset(forIconSize size: CGFloat) -> CGFloat {
        (size * badgeOffsetShare).rounded()
    }
}
