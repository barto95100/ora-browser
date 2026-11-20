import AppKit
import SwiftUI

/// The settings: one window of their own, like Arc's, kept beside the browser
/// windows (normal or private). Opening them again brings that window to the
/// front, at the section asked for. It keeps its size, position and last
/// section.
@MainActor
enum SettingsWindow {
    /// Its scene, a single `Window` (see `OmbreApp`).
    static let sceneID = "settings"
    /// The section shown, kept between launches.
    static let selectionKey = "settings.selectedTab"
    /// Its size and position.
    static let frameName = "OmbreSettingsWindow"
    /// The list of sections: always shown, this wide.
    static let sidebarWidth: CGFloat = 210
    /// The section's page at the window's smallest size.
    static let minimumDetailWidth: CGFloat = 560
    /// Room around the list: on macOS 26 it floats, a glass panel inset
    /// from the window's edges; before, it fills its side.
    static var sidebarInset: CGFloat {
        if #available(macOS 26, *) { return 8 }
        return 0
    }

    static var minimumSize: CGSize {
        CGSize(width: sidebarWidth + 2 * sidebarInset + 1 + minimumDetailWidth, height: 480)
    }

    /// The window, while it is open.
    private(set) weak static var window: NSWindow?

    /// Shows the settings, at `section` if given; `open` is the caller's
    /// `openWindow`, which makes the window when there is none.
    static func show(_ section: SettingsTab? = nil, opening open: OpenWindowAction) {
        show(section, existing: window) {
            open(id: sceneID)
        }
    }

    /// The window in front if it is open, else `open` makes it (a window
    /// closed but not freed yet is made again by its scene).
    static func show(
        _ section: SettingsTab?,
        existing: NSWindow?,
        defaults: UserDefaults = .standard,
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized },
        reveal: @MainActor (NSWindow) -> Void = bringToFront,
        open: () -> Void
    ) {
        if let section { defaults.set(section.rawValue, forKey: selectionKey) }
        guard let existing, isOpen(existing) else {
            open()
            return
        }
        reveal(existing)
    }

    private static func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The sections used to be in a split view, which kept its list folded
    /// (from a drag of its edge) between launches: that state is dropped.
    static func forgetFoldedSections(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("NSSplitView Subview Frames settings") // no translation
        {
            defaults.removeObject(forKey: key)
        }
    }

    /// The section to show.
    static func selection(in defaults: UserDefaults = .standard) -> SettingsTab {
        defaults.string(forKey: selectionKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    /// Called by the window's content once it is in its window: keeps its
    /// size and position under `frameName`.
    static func adopt(_ newWindow: NSWindow) {
        guard newWindow !== window else { return }
        // A window closed but not freed yet keeps the name: the new one
        // could not save its frame under it.
        window?.setFrameAutosaveName("")
        window = newWindow
        forgetFoldedSections()
        newWindow.setFrameUsingName(frameName)
        newWindow.setFrameAutosaveName(frameName)
        newWindow.tabbingMode = .disallowed
    }
}

/// Hands the settings window to `SettingsWindow` once the view is in it.
struct SettingsWindowAdopter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AdoptingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AdoptingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindow.adopt(window) }
        }
    }
}
