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
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private let hint = QuitHintPanel()

    func reply(to event: NSEvent?) -> NSApplication.TerminateReply {
        let decision = QuitDecision.decide(
            behavior: SettingsStore.shared.quitBehavior,
            isQuitKey: QuitDecision.isQuitKey(event),
            isConfirmed: isConfirmed
        )
        switch decision {
        case .quit:
            return .terminateNow
        case .ask:
            return askToQuit() ? .terminateNow : .terminateCancel
        case .hold:
            if let event { startHold(with: event) }
            return .terminateCancel
        }
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
            MainActor.assumeIsolated { self?.holdEnded(token) }
        }
    }

    private func release() {
        guard hold.released() else { return }
        stopWatching()
        // The hint stays a moment, to be read.
        hint.hide(after: 1.5)
    }

    private func holdEnded(_ token: Int) {
        guard hold.elapsed(token, isCommandDown: NSEvent.modifierFlags.contains(.command)) else { return }
        stopWatching()
        hint.hide(after: 0)
        isConfirmed = true
        NSApp.terminate(nil)
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

    /// The tabs of every space (favorites and pinned included).
    private var openTabCount: Int {
        let manager = BrowserWindows.frontTabManager
            ?? BrowserWindows.tabManagers.objectEnumerator()?.nextObject() as? TabManager
        return (try? manager?.modelContext.fetchCount(FetchDescriptor<Tab>())) ?? 0
    }
}

/// « Hold ⌘Q to Quit », small and centered on the screen, over every window
/// (a glass capsule on macOS 26). It never takes the keys or the mouse.
@MainActor
private final class QuitHintPanel {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(shortcut: String) {
        hideWork?.cancel()
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
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated { panel.orderOut(nil) }
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
