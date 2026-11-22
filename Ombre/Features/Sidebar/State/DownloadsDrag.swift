import CoreGraphics
import os.log

/// The drag between the downloads and the first space (the downloads sit
/// before it): how far it moves the sidebar, and where it settles. Settled,
/// the sidebar always shows one whole page, the downloads or the spaces,
/// never a part of each.
enum DownloadsDrag {
    enum Outcome: Equatable {
        case showDownloads
        case hideDownloads
        /// Back to the page the drag started from.
        case stay
    }

    /// The offset a drag gives the sidebar: toward the spaces when the
    /// downloads are shown (positive), toward the downloads from the first
    /// space (negative), none otherwise.
    static func offset(translation: CGFloat, showingDownloads: Bool, selectedIndex: Int) -> CGFloat {
        if showingDownloads { return max(translation, 0) }
        if selectedIndex == 0 { return min(translation, 0) }
        return 0
    }

    /// Where a drag that ended settles: far enough (a quarter of the
    /// sidebar), or thrown, it changes page.
    static func outcome(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        width: CGFloat,
        showingDownloads: Bool,
        selectedIndex: Int
    ) -> Outcome {
        let threshold = width * 0.25
        if showingDownloads {
            let far = translation > threshold || predictedTranslation > threshold * 2
            return far ? .hideDownloads : .stay
        }
        guard selectedIndex == 0 else { return .stay }
        let far = -translation > threshold || -predictedTranslation > threshold * 2
        return far ? .showDownloads : .stay
    }

    /// 0: the spaces are shown, 1: the downloads, in between while a drag
    /// moves the sidebar.
    static func progress(showingDownloads: Bool, offset: CGFloat, width: CGFloat) -> CGFloat {
        let base: CGFloat = showingDownloads ? 1 : 0
        return min(1, max(0, base - offset / max(width, 1)))
    }

    static func isBetweenPages(_ progress: CGFloat) -> Bool {
        progress > 0 && progress < 1
    }

    private static let logger = Logger(category: "Sidebar")

    /// A drag that left the sidebar between two pages (cancelled without an
    /// end, or a change of page during the drag): put back on a whole page.
    static func logReset(_ reason: String, offset: CGFloat) {
        let place = "sidebar between the downloads and the spaces" // not shown
        let offset = Int(offset)
        logger.notice("\(place, privacy: .public) (\(reason, privacy: .public), \(offset) pt): reset") // not shown
    }
}
