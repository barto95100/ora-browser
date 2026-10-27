import AppKit
import SwiftUI

/// Keeps a background tab's page attached to the window, hidden behind the
/// displayed page, while its video is in Picture in Picture.
///
/// Pages of background tabs are normally detached from the window to save
/// resources, but WebKit can only bring a video back from Picture in Picture
/// ("back to tab") into a page that is in a window. Only tabs in Picture in
/// Picture are parked, and only for that duration.
///
/// The parked page is placed outside the window, at its usual size: still in
/// the window and visible for WebKit (hiding it breaks "back to tab"), but the
/// mouse can never be over it, so it does not change the cursor or show its
/// tooltips through the displayed page (upstream issue 173).
struct ParkedBrowserPageView: NSViewRepresentable {
    let page: BrowserPage

    func makeNSView(context: Context) -> BrowserPageHostView {
        let hostView = BrowserPageHostView(frame: .zero)
        hostView.keepsContentOutsideWindow = true
        park(page, in: hostView)
        return hostView
    }

    func updateNSView(_ hostView: BrowserPageHostView, context: Context) {
        park(page, in: hostView)
    }

    /// Hosting is deferred to the next run loop pass so the visible host has
    /// released the page first when the user switches away from its tab; a
    /// page still shown elsewhere is never taken.
    private func park(_ page: BrowserPage, in hostView: BrowserPageHostView) {
        DispatchQueue.main.async { [weak hostView, weak page] in
            guard let hostView, let page else { return }
            let contentView = page.contentView
            guard hostView.hostedContentView !== contentView, contentView.superview == nil else { return }
            hostView.host(contentView: contentView)
        }
    }
}
