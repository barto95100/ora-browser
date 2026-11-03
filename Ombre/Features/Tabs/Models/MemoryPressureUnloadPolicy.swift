import Foundation

/// How hard macOS says memory is running low.
enum MemoryPressureLevel {
    case warning
    case critical
}

/// Which background pages to unload when macOS reports memory pressure, like
/// Safari: on a warning, regular tabs left alone for a while; when critical,
/// every background page. Unloaded tabs stay in the sidebar and load again
/// when shown.
enum MemoryPressureUnloadPolicy {
    struct Candidate {
        let id: UUID
        let lastAccessedAt: Date?
        let type: TabType
    }

    /// Regular tabs not used for this long go first, on a warning.
    static let warningIdleTime: TimeInterval = 10 * 60

    static func tabsToUnload(_ candidates: [Candidate], level: MemoryPressureLevel, now: Date = Date()) -> [UUID] {
        switch level {
        case .critical:
            return candidates.map(\.id)
        case .warning:
            let cutoff = now.addingTimeInterval(-warningIdleTime)
            return candidates
                .filter { $0.type == .normal && ($0.lastAccessedAt ?? .distantPast) < cutoff }
                .map(\.id)
        }
    }
}
