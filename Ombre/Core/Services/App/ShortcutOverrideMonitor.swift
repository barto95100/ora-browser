import AppKit

/// Detects a second quick press of a shortcut that the app did not handle the
/// first time (the page kept it, e.g. Cmd+S on Discord).
struct ShortcutDoublePressDetector {
    /// Maximum delay between the two presses.
    static let interval: TimeInterval = 0.5

    private var lastPress: (chord: KeyChord, time: TimeInterval)?
    private var appHandledSinceLastPress = false

    /// Whether this press must go to Ombre, bypassing the page.
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

    /// Ombre handled a shortcut (a menu action was sent).
    mutating func appHandledShortcut() {
        appHandledSinceLastPress = true
    }
}

/// Pressing one of Ombre's shortcuts twice quickly reaches Ombre even when the
/// page keeps it for itself (e.g. Cmd+S on Discord or Google Docs), like Arc.
/// A single press still goes to the page first, as in Safari.
@MainActor
final class ShortcutOverrideMonitor {
    static let shared = ShortcutOverrideMonitor()

    /// Never forced: quitting or hiding Ombre by accident.
    private static let excludedShortcutIDs: Set<String> = [
        KeyboardShortcuts.App.quit.id,
        KeyboardShortcuts.App.hide.id,
        // Not a menu item: only while typing in the address bar.
        KeyboardShortcuts.Address.askAI.id
    ]

    private var detector = ShortcutDoublePressDetector()
    private var keyMonitor: Any?
    private var menuObserver: NSObjectProtocol?

    func start() {
        guard keyMonitor == nil else { return }

        // A menu action means Ombre got the shortcut: no need to force the next press.
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
            // ⌘ and a key of the digit row on AZERTY: that digit (see `ShortcutKeyRemap`).
            let event = ShortcutKeyRemap.remapped(event) ?? event
            let forwardedToApp = MainActor.assumeIsolated {
                self?.forwardsToApp(event) ?? false
            }
            return forwardedToApp ? nil : event
        }
    }

    /// Whether the press was sent straight to Ombre's menu (and must not reach the page).
    private func forwardsToApp(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !event.isARepeat,
              let chord = KeyChord(fromEvent: event)
        else {
            return false
        }
        // The Developer menu's keys never go to the page first, as in Safari:
        // WebKit takes ⌥⌘C for ⌘C (Copy) and keeps it from the menu.
        if Self.goesFirstToApp(chord, inspectorAllowed: SettingsStore.shared.developerToolsEnabled) {
            return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        }
        guard Self.isOverridable(chord), detector.keyPressed(chord, at: event.timestamp) else {
            return false
        }

        // Second quick press: straight to Ombre's menu, without going through the page.
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }

    /// The shortcuts of View › Developer, while "Allow Web Inspector" is on.
    static func goesFirstToApp(
        _ chord: KeyChord,
        inspectorAllowed: Bool,
        chord current: @MainActor (KeyboardShortcutDefinition) -> KeyChord = { $0.currentChord }
    ) -> Bool {
        guard inspectorAllowed else { return false }
        return [KeyboardShortcuts.Developer.webInspector, KeyboardShortcuts.Developer.javaScriptConsole]
            .contains { current($0).isSameKeys(as: chord) }
    }

    static func isOverridable(_ chord: KeyChord) -> Bool {
        KeyboardShortcuts.allShortcuts.contains {
            $0.currentChord == chord && !excludedShortcutIDs.contains($0.id)
        }
    }
}
