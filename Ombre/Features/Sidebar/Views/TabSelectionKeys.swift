import AppKit
import SwiftUI

/// Escape ends the sidebar's selection of several tabs, wherever the focus
/// is in its window (a page included: it doesn't get that Escape). Listened
/// to only while tabs are selected.
@MainActor
final class TabSelectionEscapeMonitor {
    private var monitor: Any?

    func start(window: @escaping @MainActor () -> NSWindow?, onEscape: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread. Only a Bool leaves the
            // isolated closure: NSEvent is not Sendable.
            let isEscape = event.keyCode == 53 && event.modifierFlags
                .isDisjoint(with: .deviceIndependentFlagsMask.subtracting(.capsLock))
            let eventWindow = event.window
            let handled = MainActor.assumeIsolated {
                guard isEscape, let window = window(), eventWindow === window else { return false }
                onEscape()
                return true
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The selection's keys and what VoiceOver hears of it, for a window's sidebar.
struct TabSelectionKeys: ViewModifier {
    @ObservedObject var tabManager: TabManager
    let window: NSWindow?
    @State private var escape = TabSelectionEscapeMonitor()

    func body(content: Content) -> some View {
        content
            .onChange(of: tabManager.selectedTabIDs.isEmpty) { _, isEmpty in
                updateEscape(isEmpty: isEmpty)
            }
            // The floating sidebar comes and goes: the selection may still be there.
            .onAppear { updateEscape(isEmpty: tabManager.selectedTabIDs.isEmpty) }
            .onChange(of: tabManager.selectedTabIDs.count) { _, count in
                // Cleared after an action of the menu: the action says enough.
                if count > 0 { announce(count: count) }
            }
            .onDisappear { escape.stop() }
    }

    private func updateEscape(isEmpty: Bool) {
        guard !isEmpty else {
            escape.stop()
            return
        }
        let manager = tabManager
        let target = window
        escape.start(window: { [weak target, weak manager] in
            // Tabs closed or moved away: nothing selected to clear, the
            // Escape goes on to the page.
            manager?.selectedTabs.isEmpty == false ? target : nil
        }, onEscape: { [weak manager] in
            manager?.clearTabSelection()
            Self.announce(count: 0)
        })
    }

    private func announce(count: Int) {
        Self.announce(count: count)
    }

    private static func announce(count: Int) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: TabSelectionAccessibility.announcement(count: count),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
