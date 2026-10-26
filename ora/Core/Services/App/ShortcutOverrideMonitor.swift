import AppKit

/// Detects a second quick press of a shortcut that the app did not handle the
/// first time (the page kept it, e.g. Cmd+S on Discord).
struct ShortcutDoublePressDetector {
    /// Maximum delay between the two presses.
    static let interval: TimeInterval = 0.5

    private var lastPress: (chord: KeyChord, time: TimeInterval)?
    private var appHandledSinceLastPress = false

    /// Whether this press must go to Ora, bypassing the page.
    mutating func keyPressed(_ chord: KeyChord, at time: TimeInterval) -> Bool {
        if let lastPress, lastPress.chord == chord,
           time - lastPress.time <= Self.interval,
           !appHandledSinceLastPress
        {
            self.lastPress = nil
            return true
        }
        lastPress = (chord, time)
        appHandledSinceLastPress = false
        return false
    }

    /// Ora handled a shortcut (a menu action was sent).
    mutating func appHandledShortcut() {
        appHandledSinceLastPress = true
    }
}

/// Pressing one of Ora's shortcuts twice quickly reaches Ora even when the
/// page keeps it for itself (e.g. Cmd+S on Discord or Google Docs), like Arc.
/// A single press still goes to the page first, as in Safari.
@MainActor
final class ShortcutOverrideMonitor {
    static let shared = ShortcutOverrideMonitor()

    /// Never forced: quitting or hiding Ora by accident.
    private static let excludedShortcutIDs: Set<String> = [
        KeyboardShortcuts.App.quit.id,
        KeyboardShortcuts.App.hide.id
    ]

    private var detector = ShortcutDoublePressDetector()
    private var keyMonitor: Any?
    private var menuObserver: NSObjectProtocol?

    func start() {
        guard keyMonitor == nil else { return }

        // A menu action means Ora got the shortcut: no need to force the next press.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didSendActionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.detector.appHandledShortcut()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let forwardedToOra = MainActor.assumeIsolated {
                self?.forwardsToOra(event) ?? false
            }
            return forwardedToOra ? nil : event
        }
    }

    /// Whether the press was sent straight to Ora's menu (and must not reach the page).
    private func forwardsToOra(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !event.isARepeat,
              let chord = KeyChord(fromEvent: event),
              Self.isOverridable(chord),
              detector.keyPressed(chord, at: event.timestamp)
        else {
            return false
        }

        // Second quick press: straight to Ora's menu, without going through the page.
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }

    static func isOverridable(_ chord: KeyChord) -> Bool {
        KeyboardShortcuts.allShortcuts.contains {
            $0.currentChord == chord && !excludedShortcutIDs.contains($0.id)
        }
    }
}
