import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "MemoryPressure")

extension TabManager {
    /// Like Safari: when macOS reports memory pressure, background pages are
    /// unloaded right away instead of after their idle delay.
    func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : .warning
            MainActor.assumeIsolated {
                self?.unloadBackgroundPages(for: level)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    /// Unloads background pages chosen by `MemoryPressureUnloadPolicy`. Pages
    /// shown in a window (any window, or kept for Picture in Picture), playing
    /// media or using the camera or microphone are kept.
    func unloadBackgroundPages(for level: MemoryPressureLevel, now: Date = Date()) {
        let containers = (try? modelContext.fetch(FetchDescriptor<TabContainer>())) ?? []
        let loaded = containers.flatMap(\.tabs).filter { tab in
            guard let page = tab.browserPage else { return false }
            return page.window == nil
                && tab.id != activeTab?.id
                && !tab.isPlayingMedia
                && !tab.mediaCaptureState.isCapturing
        }
        let candidates = loaded.map {
            MemoryPressureUnloadPolicy.Candidate(id: $0.id, lastAccessedAt: $0.lastAccessedAt, type: $0.type)
        }
        let unloaded = Set(MemoryPressureUnloadPolicy.tabsToUnload(candidates, level: level, now: now))
        for tab in loaded where unloaded.contains(tab.id) {
            tab.destroyWebView()
        }
        let levelName = String(describing: level)
        logger.info("Memory pressure (\(levelName)): unloaded \(unloaded.count) of \(loaded.count) pages")
    }
}
