import AppKit

/// What becomes of a browser window Little Ombre hid when the last Little
/// Ombre holding it closes.
enum HiddenBrowserWindow: Equatable {
    /// Made for the link while Ombre had no window: closed, as before the link.
    case close
    /// Opened as Ombre launched (the link launched it, its windows came
    /// back): shown, as a launch would.
    case show
}

/// A link from another app while no browser window is open: SwiftUI makes
/// one to hand it over (a link is always given to a window). Little Ombre
/// then opens alone, like Little Arc: that window is hidden while a Little
/// Ombre uses it, shown by "Open in Ombre", and closed (or shown, at launch)
/// once none uses it.
extension LittleOmbreWindow {
    /// A window that appeared less than this before its link was made for it.
    static let windowForLinkDelay: Duration = .seconds(1)
    /// Ombre launched less than this before: the link launched it.
    static let launchDelay: TimeInterval = 5

    /// What to do with `browserWindow`, which handed over a link Little Ombre
    /// opened: nothing when another browser window is open (or it was there
    /// before the link), else hide it.
    static func hiding(
        _ browserWindow: NSWindow,
        appearedFor elapsed: Duration,
        otherWindows: [NSWindow],
        launchedFor launch: TimeInterval,
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized }
    ) -> HiddenBrowserWindow? {
        // Already hidden by another Little Ombre: kept hidden for this one too.
        if let held = held(browserWindow) { return held }
        guard isOpen(browserWindow), elapsed < windowForLinkDelay,
              !otherWindows.contains(where: { $0 !== browserWindow && isOpen($0) })
        else { return nil }
        return launch < launchDelay ? .show : .close
    }

    /// Hides the browser window it came from, until "Open in Ombre" or its close.
    func hideBrowserWindow(_ fate: HiddenBrowserWindow) {
        guard let browserWindow else { return }
        hiddenBrowserWindow = fate
        browserWindow.isExcludedFromWindowsMenu = true
        browserWindow.orderOut(nil)
    }

    /// Its page went to a tab: the browser window shows, for every Little
    /// Ombre that hid it.
    func showBrowserWindow() {
        guard let browserWindow else { return }
        for little in Self.openWindows where little.browserWindow === browserWindow {
            little.hiddenBrowserWindow = nil
        }
        hiddenBrowserWindow = nil
        Self.reveal(browserWindow)
    }

    /// `browserWindow` is needed (a link opens in it as a tab): shown if a
    /// Little Ombre hid it.
    static func browserWindowNeeded(_ browserWindow: NSWindow) {
        guard held(browserWindow) != nil else { return }
        for little in openWindows where little.browserWindow === browserWindow {
            little.hiddenBrowserWindow = nil
        }
        reveal(browserWindow)
    }

    /// Closed: the browser window it hid goes, once no Little Ombre uses it.
    func releaseHiddenBrowserWindow() {
        guard let fate = hiddenBrowserWindow, let browserWindow else { return }
        hiddenBrowserWindow = nil
        guard Self.held(browserWindow) == nil, !Self.isOpen(browserWindow) else { return }
        switch fate {
        case .close:
            // Once Little Ombre is gone (the window closes the Little Ombres it has).
            DispatchQueue.main.async { browserWindow.close() }
        case .show:
            Self.reveal(browserWindow)
        }
    }

    /// How another Little Ombre holds `browserWindow` hidden, if one does.
    private static func held(_ browserWindow: NSWindow) -> HiddenBrowserWindow? {
        openWindows.lazy.filter { $0.browserWindow === browserWindow }.compactMap(\.hiddenBrowserWindow).first
    }

    private static func isOpen(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized
    }

    private static func reveal(_ browserWindow: NSWindow) {
        browserWindow.isExcludedFromWindowsMenu = false
        if TestHost.isActive {
            browserWindow.orderBack(nil)
        } else {
            browserWindow.makeKeyAndOrderFront(nil)
        }
    }
}
