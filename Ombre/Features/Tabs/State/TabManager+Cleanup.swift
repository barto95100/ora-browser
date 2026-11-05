import Foundation

/// Tabs unloaded or closed after a while (Settings › General › Tab
/// Management, and each space's auto-clear).
extension TabManager {
    /// Clean up old tabs that haven't been accessed recently to preserve memory
    func cleanupOldTabs() {
        let timeout = SettingsStore.shared.tabAliveTimeout
        // Skip cleanup if set to "Never" (365 days)
        guard timeout < 365 * 24 * 60 * 60 else { return }

        let allContainers = fetchContainers()
        for container in allContainers {
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

    /// Completely remove old normal tabs that haven't been accessed for a long time
    func removeOldTabs() {
        let cutoffDate = Date().addingTimeInterval(-SettingsStore.shared.tabRemovalTimeout)
        let allContainers = fetchContainers()

        for container in allContainers {
            for tab in container.tabs {
                if let lastAccessed = tab.lastAccessedAt,
                   lastAccessed < cutoffDate,
                   !isShown(tab),
                   !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing,
                   tab.type == .normal
                {
                    closeTab(tab: tab, shouldTrackForRestore: false)
                }
            }
        }
    }

    /// Remove tabs in containers that have a per-space autoClearTabsAfter setting
    func autoClearContainerTabs() {
        let settings = SettingsStore.shared
        let allContainers = fetchContainers()

        for container in allContainers {
            let policy = settings.autoClearTabsAfter(for: container.id)
            guard let timeout = policy.seconds else { continue }

            let cutoffDate = Date().addingTimeInterval(-timeout)
            for tab in container.tabs {
                if let lastAccessed = tab.lastAccessedAt,
                   lastAccessed < cutoffDate,
                   !isShown(tab),
                   !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing,
                   tab.type == .normal
                {
                    closeTab(tab: tab)
                }
            }
        }
    }

    /// Start the automatic cleanup timer
    /// Called once, by `init`: a second timer would run beside the first.
    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanupOldTabs()
                self?.removeOldTabs()
                self?.autoClearContainerTabs()
            }
        }
    }
}
