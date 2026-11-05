import Foundation
import SwiftData

/// Tabs unloaded or closed after a while (Settings › General › Tab
/// Management, and each space's auto-clear), on `TabCleaner`'s schedule.
extension TabManager {
    /// Unloads the pages of this window's tabs not shown for a while (they
    /// stay in the sidebar).
    func unloadOldTabs() {
        let timeout = SettingsStore.shared.tabAliveTimeout
        // Skip cleanup if set to "Never" (365 days)
        guard timeout < 365 * 24 * 60 * 60 else { return }

        for container in fetchContainers() {
            for tab in container.tabs {
                // A tab in a call keeps its page, like one playing media.
                if !tab.isAlive, tab.isWebViewReady, !isShown(tab), !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing, tab.type == .normal
                {
                    tab.destroyWebView()
                }
            }
        }
    }

    /// Closes normal tabs not shown for long (the general setting, or the
    /// space's auto-clear), except those `spared` (in use in any window).
    /// Not reopened by ⌘Z: the user didn't close them.
    func closeOldTabs(sparing spared: Set<UUID>, now: Date = Date()) {
        let settings = SettingsStore.shared
        let removalCutoff = now.addingTimeInterval(-settings.tabRemovalTimeout)
        for container in fetchContainers() {
            let cutoff = settings.autoClearTabsAfter(for: container.id).seconds
                .map { max(now.addingTimeInterval(-$0), removalCutoff) } ?? removalCutoff
            for tab in container.tabs {
                if let lastAccessed = tab.lastAccessedAt, lastAccessed < cutoff,
                   !spared.contains(tab.id), !isShown(tab),
                   !tab.isPlayingMedia, !tab.mediaCaptureState.isCapturing, tab.type == .normal
                {
                    closeTab(tab: tab, shouldTrackForRestore: false)
                }
            }
        }
    }

    /// The tabs this window can't lose: shown, playing media, or using the
    /// camera or microphone (all per window).
    func tabsInUse() -> [UUID] {
        let shown = shownTabs(around: activeTab).map(\.id)
        let busy = fetchContainers().flatMap(\.tabs)
            .filter { $0.isPlayingMedia || $0.mediaCaptureState.isCapturing }
            .map(\.id)
        return shown + busy
    }
}
