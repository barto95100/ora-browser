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

    /// The window, while it is open.
    private(set) weak static var window: NSWindow?
    /// Opens the scene, from code that has no `openWindow` of its own: set
    /// by the browser windows and the menu.
    static var opener: OpenWindowAction?

    /// Shows the settings, at `section` if given.
    static func show(_ section: SettingsTab? = nil, opening open: OpenWindowAction? = nil) {
        show(section, existing: window) {
            (open ?? opener)?(id: sceneID)
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

    /// The section to show.
    static func selection(in defaults: UserDefaults = .standard) -> SettingsTab {
        defaults.string(forKey: selectionKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    /// Called by the window's content once it is in its window: keeps its
    /// size and position under `frameName`.
    static func adopt(_ newWindow: NSWindow) {
        guard newWindow !== window else { return }
        window = newWindow
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
