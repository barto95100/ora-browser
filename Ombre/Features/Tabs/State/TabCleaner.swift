import Foundation
import SwiftData

/// The app's one tab cleaner: once a minute (with leeway, so the system can
/// group it with other work), every open window unloads its old pages and
/// closes its old tabs, never one any window of its database uses. Each
/// window closes its own copy: one left behind in another window's context
/// would point to a deleted row. Windows sign in when made, out when closed.
@MainActor
final class TabCleaner {
    static let shared = TabCleaner()

    private struct Entry {
        weak var tabManager: TabManager?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var timer: Timer?

    /// The timer's leeway, for the tests.
    var timerTolerance: TimeInterval? {
        timer?.tolerance
    }

    func isCleaning(_ tabManager: TabManager) -> Bool {
        entries[ObjectIdentifier(tabManager)]?.tabManager != nil
    }

    func register(_ tabManager: TabManager) {
        entries[ObjectIdentifier(tabManager)] = Entry(tabManager: tabManager)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { TabCleaner.shared.clean() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    func unregister(_ tabManager: TabManager) {
        entries[ObjectIdentifier(tabManager)] = nil
        prune()
    }

    /// The timer's pass, over the open windows.
    func clean(now: Date = Date()) {
        prune()
        clean(entries.values.compactMap(\.tabManager), now: now)
    }

    /// One pass over `managers`: each window unloads its pages and closes
    /// its old tabs, sparing those any window of its database shows, plays
    /// media in or uses the camera or microphone in.
    func clean(_ managers: [TabManager], now: Date = Date()) {
        let managers = managers.filter { !$0.isTornDown }
        let byDatabase = Dictionary(grouping: managers) { ObjectIdentifier($0.modelContainer) }
        for windows in byDatabase.values {
            let spared = Set(windows.flatMap { $0.tabsInUse() })
            for window in windows {
                window.unloadOldTabs()
                window.closeOldTabs(sparing: spared, now: now)
            }
        }
    }

    private func prune() {
        entries = entries.filter { $0.value.tabManager != nil }
        if entries.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}
