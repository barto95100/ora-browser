import AppKit
@testable import Ombre
import SwiftUI
import Testing

/// The favorites grid follows the sidebar's width: as many columns of at least
/// 48 pt as fit, at most 6, cells and icons within their limits.
struct FavoritesGridMetricsTests {
    @Test func theNarrowestSidebarKeepsThreeColumns() {
        // A 200 pt sidebar leaves about 180 pt to the grid.
        let metrics = FavoritesGridMetrics(width: 180, count: 10)
        #expect(metrics.columns == 3)
        #expect(metrics.rows == 4)
        #expect(abs(metrics.cellWidth - 160.0 / 3) < 0.001)
        #expect(metrics.cellWidth >= FavoritesGridMetrics.minimumCellWidth)
    }

    @Test func aWiderSidebarFitsMoreColumns() {
        #expect(FavoritesGridMetrics(width: 240, count: 10).columns == 4)
        #expect(FavoritesGridMetrics(width: 300, count: 10).columns == 5)
        #expect(FavoritesGridMetrics(width: 360, count: 10).columns == 6)
    }

    @Test func neverMoreThanSixColumns() {
        let metrics = FavoritesGridMetrics(width: 900, count: 20)
        #expect(metrics.columns == FavoritesGridMetrics.maximumColumns)
        #expect(metrics.cellHeight == FavoritesGridMetrics.cellHeights.upperBound)
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: metrics.cellHeight) == FavoritesGridMetrics.iconSizes
            .upperBound)
    }

    @Test func columnsNeverGetNarrowerThanTheMinimum() {
        for width in stride(from: CGFloat(48), through: 800, by: 1) {
            let metrics = FavoritesGridMetrics(width: width, count: 12)
            #expect(metrics.cellWidth >= FavoritesGridMetrics.minimumCellWidth - 0.001, "width \(width)")
        }
    }

    @Test func columnsGrowWithTheWidthWithoutGoingBack() {
        var previous = 0
        for width in stride(from: CGFloat(0), through: 800, by: 0.5) {
            let columns = FavoritesGridMetrics(width: width, count: 12).columns
            #expect(columns >= previous, "width \(width)")
            previous = columns
        }
    }

    @Test func fewFavoritesFillTheRow() {
        let metrics = FavoritesGridMetrics(width: 240, count: 2)
        #expect(metrics.columns == 2)
        #expect(metrics.rows == 1)
        #expect(metrics.cellWidth == 115)
        // As tall as a full row's cells: a lone favorite isn't taller.
        #expect(metrics.cellHeight == FavoritesGridMetrics(width: 240, count: 10).cellHeight)
        #expect(FavoritesGridMetrics(width: 240, count: 1).cellWidth == 240)
    }

    @Test func cellHeightsStayWithinTheirLimits() {
        for width in stride(from: CGFloat(0), through: 900, by: 3) {
            let height = FavoritesGridMetrics(width: width, count: 8).cellHeight
            #expect(FavoritesGridMetrics.cellHeights.contains(height), "width \(width)")
        }
    }

    @Test func cellsTileTheWidthWithoutOverlapping() {
        for width in [CGFloat(180), 233, 300, 412.5, 600] {
            let metrics = FavoritesGridMetrics(width: width, count: 9)
            let frames = (0 ..< 9).map(metrics.frame(at:))
            for frame in frames {
                #expect(frame.minX >= 0 && frame.maxX <= width + 0.001)
            }
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    #expect(!frame.intersects(other), "width \(width)")
                }
            }
            // On whole points; the last cell of a full row reaches the edge.
            for frame in frames {
                #expect(frame.minX == frame.minX.rounded() && frame.width == frame.width.rounded())
            }
            #expect(width - metrics.frame(at: metrics.columns - 1).maxX < 1)
            #expect(abs(metrics.frame(at: 8).maxY - metrics.height) < 0.001)
        }
    }

    @Test func theSecondRowStartsBelowTheFirst() {
        let metrics = FavoritesGridMetrics(width: 180, count: 5)
        let frame = metrics.frame(at: 4)
        #expect(abs(frame.minX - (metrics.cellWidth + FavoritesGridMetrics.spacing)) < 1)
        #expect(abs(frame.minY - (metrics.cellHeight + FavoritesGridMetrics.spacing)) < 0.001)
    }

    @Test func rowsGrowContinuouslyWithTheWidth() {
        // 48 pt at the narrowest sidebar, as before; never a jump of more
        // than a point when a column is added.
        #expect(FavoritesGridMetrics(width: 180, count: 8).cellHeight == 48)
        var previous = FavoritesGridMetrics(width: 100, count: 8).cellHeight
        for width in stride(from: CGFloat(100), through: 800, by: 0.5) {
            let height = FavoritesGridMetrics(width: width, count: 8).cellHeight
            #expect(height >= previous && height - previous <= 1, "width \(width)")
            previous = height
        }
    }

    @Test func tooNarrowForOneCellStillShowsThemAll() {
        let metrics = FavoritesGridMetrics(width: 30, count: 3)
        #expect(metrics.columns == 1)
        #expect(metrics.rows == 3)
        #expect(metrics.cellWidth == 30)
        #expect(metrics.cellHeight == FavoritesGridMetrics.cellHeights.lowerBound)
        #expect(FavoritesGridMetrics(width: 0, count: 0).rows == 1)
    }

    @Test func theIconKeepsItsShareOfTheCell() {
        // 20 pt in a 48 pt cell, as before.
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: 48) == 20)
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: 56) == 23)
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: 44) == 18)
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: 200) == FavoritesGridMetrics.iconSizes.upperBound)
        #expect(FavoritesGridMetrics.iconSize(forCellHeight: 10) == FavoritesGridMetrics.iconSizes.lowerBound)
    }

    @Test func badgesFollowTheIconsCorner() {
        #expect(FavoritesGridMetrics.badgeOffset(forIconSize: 20) == 7)
        #expect(FavoritesGridMetrics.badgeOffset(forIconSize: 18) == 6)
        #expect(FavoritesGridMetrics.badgeOffset(forIconSize: 23) == 8)
    }
}

/// The SwiftUI layout gives the grid the metrics' height at each width (never
/// put on screen).
@MainActor
struct FavoritesGridLayoutTests {
    @Test func theLayoutTakesTheMetricsHeight() {
        for (width, count) in [(CGFloat(180), 7), (240, 7), (400, 7), (240, 2)] {
            let grid = FavoritesGridLayout {
                ForEach(0 ..< count, id: \.self) { _ in Color.red }
            }
            .frame(width: width)
            let host = NSHostingView(rootView: grid)
            let expected = FavoritesGridMetrics(width: width, count: count).height
            #expect(abs(host.fittingSize.height - expected) < 0.5, "width \(width), \(count) favorites")
        }
    }
}
