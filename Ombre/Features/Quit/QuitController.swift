import AppKit
import SwiftData
import SwiftUI

/// Answers the app's requests to quit (`applicationShouldTerminate`) as
/// Settings › General › To Quit says: ⌘Q held, a question, or at once.
/// Nothing belongs to a window: ⌘Q works the same from a browser window,
/// Little Ombre or the settings.
@MainActor
final class QuitController {
    static let shared = QuitController()

    private var hold = QuitHold()
    /// Quitting was confirmed (⌘Q held long enough, or Quit in the question).
    private var isConfirmed = false
    /// The question is showing: another request waits for its answer.
    private var isAsking = false
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private let hint = QuitHintPanel()

    func reply(to event: NSEvent?) -> NSApplication.TerminateReply {
        let decision = QuitDecision.decide(
            behavior: SettingsStore.shared.quitBehavior,
            isQuitKey: QuitDecision.isQuitKey(event, isAppleEvent: isQuitAppleEvent),
            isConfirmed: isConfirmed
        )
        switch decision {
        case .quit:
            return .terminateNow
        case .ask:
            guard !isAsking else { return .terminateCancel }
            return askToQuit() ? .terminateNow : .terminateCancel
        case .hold:
            if let event { startHold(with: event) }
            return .terminateCancel
        }
    }

    /// The Dock or logging out asks to quit (an Apple event).
    private var isQuitAppleEvent: Bool {
        NSAppleEventManager.shared().currentAppleEvent?.eventID == kAEQuitApplication
    }

    // MARK: - Holding ⌘Q

    private func startHold(with event: NSEvent) {
        guard let token = hold.pressed() else { return }
        let keyCode = event.keyCode
        hint.show(shortcut: KeyChord(fromEvent: event)?.display ?? "⌘Q")
        // Releasing the key or ⌘ cancels; so does leaving Ombre.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] event in
            let isRelease = event.type == .keyUp
                ? event.keyCode == keyCode
                : !event.modifierFlags.contains(.command)
            if isRelease {
                MainActor.assumeIsolated { self?.release() }
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
        // One delay per press, not a timer that keeps running.
        DispatchQueue.main.asyncAfter(deadline: .now() + QuitHold.duration) { [weak self] in
            MainActor.assumeIsolated { self?.holdEnded(token, keyCode: keyCode) }
        }
    }

    private func release() {
        guard hold.released() else { return }
        stopWatching()
        // The hint stays a moment, to be read.
        hint.hide(after: 1.5)
    }

    /// Quits only if ⌘ and the key are still down (checked on the keyboard
    /// itself: a release we did not see never quits).
    private func holdEnded(_ token: Int, keyCode: UInt16) {
        let isStillHeld = NSEvent.modifierFlags.contains(.command)
            && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        switch hold.elapsed(token, isStillHeld: isStillHeld) {
        case .stale:
            return
        case .cancelled:
            stopWatching()
            hint.hide(after: 1.5)
        case .quit:
            stopWatching()
            hint.hide(after: 0)
            isConfirmed = true
            NSApp.terminate(nil)
            // Back here only if quitting was stopped (a page or the system).
            isConfirmed = false
        }
    }

    private func stopWatching() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // MARK: - Asking

    /// A standard alert with what will close; « Don't Ask Again » makes ⌘Q
    /// quit at once from then on.
    private func askToQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Ombre?")
        alert.informativeText = QuitConfirmationText.message(windows: openWindowCount, tabs: openTabCount)
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don’t Ask Again")
        NSApp.activate()
        isAsking = true
        defer { isAsking = false }
        let quits = alert.runModal() == .alertFirstButtonReturn
        if quits, alert.suppressionButton?.state == .on {
            SettingsStore.shared.quitBehavior = .immediately
        }
        return quits
    }

    /// Browser windows (normal and private) and Little Ombres, open or
    /// minimized.
    private var openWindowCount: Int {
        let browsers = BrowserWindows.browsing.allObjects.filter { $0.isVisible || $0.isMiniaturized }
        return browsers.count + LittleOmbreWindow.openWindows.count
    }

    /// The tabs of every space, and those of private windows (each has its
    /// own store; the normal windows share theirs).
    private var openTabCount: Int {
        let managers = BrowserWindows.allTabManagers.objectEnumerator()?.allObjects as? [TabManager] ?? []
        var counted = Set<ObjectIdentifier>()
        return managers.reduce(0) { total, manager in
            let context = manager.modelContext
            guard counted.insert(ObjectIdentifier(context)).inserted else { return total }
            return total + ((try? context.fetchCount(FetchDescriptor<Tab>())) ?? 0)
        }
    }
}

/// « Hold ⌘Q to Quit », small and centered on the screen, over every window
/// (a glass capsule on macOS 26). It never takes the keys or the mouse.
@MainActor
private final class QuitHintPanel {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Each show; a fade from an earlier one does not hide this one.
    private var generation = 0

    func show(shortcut: String) {
        hideWork?.cancel()
        generation += 1
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: QuitHintView(shortcut: shortcut))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - host.fittingSize.width / 2,
                y: frame.midY - host.fittingSize.height / 2
            ))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval) {
        hideWork?.cancel()
        let shown = generation
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        if self.generation == shown { panel.orderOut(nil) }
                    }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct QuitHintView: View {
    let shortcut: String

    var body: some View {
        Text("Hold \(shortcut) to Quit")
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .modifier(QuitHintBackground())
            .padding(20)
    }
}

private struct QuitHintBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}
