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
    private var heldKeyCode: UInt16 = 0
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
        guard let token = hold.pressed(isRepeat: event.isARepeat) else { return }
        let keyCode = event.keyCode
        heldKeyCode = keyCode
        hint.show(shortcut: KeyChord(fromEvent: event)?.display ?? "⌘Q", filling: QuitHold.duration)
        if keyMonitor == nil {
            // The held key's repeats are absorbed: Ombre keeps them, none
            // reaches the menu again or another app. Releasing the key or ⌘
            // quits once the hint is full, and cancels before.
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .flagsChanged]
            ) { [weak self] event in
                let absorbs = MainActor.assumeIsolated { self?.absorbs(event) ?? false }
                return absorbs ? nil : event
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.abandon() }
            }
        }
        // One delay per press, not a timer that keeps running.
        DispatchQueue.main.asyncAfter(deadline: .now() + QuitHold.duration) { [weak self] in
            MainActor.assumeIsolated { self?.holdEnded(token, keyCode: keyCode) }
        }
    }

    /// The key events while holding: whether to absorb this one.
    private func absorbs(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return hold.absorbs(keyDownOf: event.keyCode, isRepeat: event.isARepeat, heldKeyCode: heldKeyCode)
        case .keyUp where event.keyCode == heldKeyCode:
            release()
        case .flagsChanged where !event.modifierFlags.contains(.command):
            release()
        default:
            break
        }
        return false
    }

    private func release() {
        switch hold.released() {
        case .nothing:
            return
        case .cancelled:
            stopWatching()
            // The hint empties and stays a moment, to be read.
            hint.cancel()
        case .quit:
            stopWatching()
            hint.hide(after: 0)
            isConfirmed = true
            NSApp.terminate(nil)
            // Back here only if quitting was stopped (a page or the system).
            isConfirmed = false
        }
    }

    /// Ombre left the front during the hold: the hint goes, nothing else.
    private func abandon() {
        guard hold.abandoned() else { return }
        stopWatching()
        hint.hide(after: 0)
    }

    /// The hint is full if ⌘ and the key are still down (checked on the
    /// keyboard itself: a release we did not see never arms).
    private func holdEnded(_ token: Int, keyCode: UInt16) {
        let isStillHeld = NSEvent.modifierFlags.contains(.command)
            && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        switch hold.elapsed(token, isStillHeld: isStillHeld) {
        case .stale:
            return
        case .cancelled:
            stopWatching()
            hint.cancel()
        case .armed:
            hint.arm()
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

/// What the hint shows: it fills while ⌘Q is held, then says to release.
@MainActor
private final class QuitHintModel: ObservableObject {
    @Published var shortcut = "⌘Q"
    /// How long the ring takes to fill.
    @Published var duration: TimeInterval = 1
    @Published var isArmed = false
    /// Released before the ring was full: it empties.
    @Published var isCancelled = false
}

/// « Hold ⌘Q to Quit », small and centered on the screen, over every window
/// (a glass capsule on macOS 26). It never takes the keys, the focus or the
/// mouse.
@MainActor
private final class QuitHintPanel {
    private var panel: NSPanel?
    private let model = QuitHintModel()
    private var hideWork: DispatchWorkItem?
    /// Each show; a fade from an earlier one does not hide this one.
    private var generation = 0

    func show(shortcut: String, filling duration: TimeInterval) {
        hideWork?.cancel()
        generation += 1
        model.shortcut = shortcut
        model.duration = duration
        model.isArmed = false
        model.isCancelled = false
        let panel = panel ?? makePanel()
        self.panel = panel
        // A new view each time: the ring starts empty, and the size is the
        // one of this shortcut.
        let host = NSHostingView(rootView: QuitHintView(model: model))
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Full: « Release to Quit ».
    func arm() {
        withAnimation(.easeOut(duration: 0.15)) { model.isArmed = true }
    }

    /// Released too soon: the ring empties, the hint goes a moment later.
    func cancel() {
        model.isCancelled = true
        hide(after: 1.5)
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
    @ObservedObject var model: QuitHintModel

    var body: some View {
        HStack(spacing: 10) {
            QuitHintRing(duration: model.duration, isArmed: model.isArmed, isCancelled: model.isCancelled)
            // Both texts take the same place: the capsule does not resize.
            ZStack(alignment: .leading) {
                Text("Hold \(model.shortcut) to Quit").opacity(model.isArmed ? 0 : 1)
                Text("Release to Quit").opacity(model.isArmed ? 1 : 0)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .padding(.leading, 14)
        .padding(.trailing, 22)
        .padding(.vertical, 12)
        .modifier(QuitHintBackground())
        .padding(20)
    }
}

/// A ring that fills while ⌘Q is held (once, on appearing: no animation
/// that keeps running), then shows a check; it empties when cancelled.
private struct QuitHintRing: View {
    let duration: TimeInterval
    let isArmed: Bool
    let isCancelled: Bool
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: isArmed ? 1 : progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .opacity(isArmed ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
        .onChange(of: isCancelled) { _, cancelled in
            guard cancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
    }
}

private struct QuitHintBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *), GlassEffects.isActiveNow {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}
