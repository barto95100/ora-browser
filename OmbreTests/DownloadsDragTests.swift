import CoreGraphics
@testable import Ombre
import Testing

/// The drag between the downloads and the first space: it follows the
/// fingers only toward a page, and once settled the sidebar shows one whole
/// page, never a part of each.
struct DownloadsDragTests {
    private let width: CGFloat = 240

    @Test func fromTheFirstSpaceOnlyADragTowardTheDownloadsMoves() {
        #expect(DownloadsDrag.offset(translation: -80, showingDownloads: false, selectedIndex: 0) == -80)
        #expect(DownloadsDrag.offset(translation: 80, showingDownloads: false, selectedIndex: 0) == 0)
    }

    @Test func fromAnotherSpaceNoDragMoves() {
        #expect(DownloadsDrag.offset(translation: -80, showingDownloads: false, selectedIndex: 2) == 0)
        #expect(DownloadsDrag.offset(translation: 80, showingDownloads: false, selectedIndex: 2) == 0)
    }

    @Test func fromTheDownloadsOnlyADragTowardTheSpacesMoves() {
        #expect(DownloadsDrag.offset(translation: 80, showingDownloads: true, selectedIndex: 0) == 80)
        #expect(DownloadsDrag.offset(translation: -80, showingDownloads: true, selectedIndex: 0) == 0)
    }

    @Test func aDragComingBackFollowsTheFingers() {
        // Left then back past the start: no offset kept from the way out.
        #expect(DownloadsDrag.offset(translation: 10, showingDownloads: false, selectedIndex: 0) == 0)
    }

    @Test func aFarOrThrownDragChangesPage() {
        #expect(outcome(-70, showing: false) == .showDownloads)
        #expect(outcome(-20, predicted: -130, showing: false) == .showDownloads)
        #expect(outcome(70, showing: true) == .hideDownloads)
        #expect(outcome(20, predicted: 130, showing: true) == .hideDownloads)
    }

    @Test func aShortDragGoesBackToItsPage() {
        #expect(outcome(-50, showing: false) == .stay)
        #expect(outcome(50, showing: true) == .stay)
        // The wrong way, or from another space: no change of page.
        #expect(outcome(120, showing: false) == .stay)
        #expect(outcome(-120, showing: true) == .stay)
        #expect(outcome(-120, showing: false, index: 1) == .stay)
    }

    @Test func withoutADragTheSidebarShowsAWholePage() {
        for showing in [false, true] {
            let progress = DownloadsDrag.progress(showingDownloads: showing, offset: 0, width: width)
            #expect(progress == (showing ? 1 : 0))
            #expect(!DownloadsDrag.isBetweenPages(progress))
        }
    }

    /// The defect: a drag cancelled halfway kept its offset, and the sidebar
    /// stayed half downloads, half spaces.
    @Test func anOffsetLeftByADragIsBetweenPages() {
        let half = DownloadsDrag.progress(showingDownloads: false, offset: -width / 2, width: width)
        #expect(half == 0.5)
        #expect(DownloadsDrag.isBetweenPages(half))
        let back = DownloadsDrag.progress(showingDownloads: true, offset: width / 4, width: width)
        #expect(back == 0.75)
        #expect(DownloadsDrag.isBetweenPages(back))
    }

    @Test func progressStaysWithinThePages() {
        #expect(DownloadsDrag.progress(showingDownloads: false, offset: -2 * width, width: width) == 1)
        #expect(DownloadsDrag.progress(showingDownloads: true, offset: 2 * width, width: width) == 0)
        #expect(DownloadsDrag.progress(showingDownloads: false, offset: -10, width: 0) == 1)
    }

    private func outcome(
        _ translation: CGFloat,
        predicted: CGFloat? = nil,
        showing: Bool,
        index: Int = 0
    ) -> DownloadsDrag.Outcome {
        DownloadsDrag.outcome(
            translation: translation,
            predictedTranslation: predicted ?? translation,
            width: width,
            showingDownloads: showing,
            selectedIndex: index
        )
    }
}
