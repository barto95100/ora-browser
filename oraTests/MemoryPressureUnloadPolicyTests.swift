import Foundation
@testable import Ora
import Testing

struct MemoryPressureUnloadPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private let recent = UUID()
    private let old = UUID()
    private let oldPinned = UUID()
    private let neverUsed = UUID()

    private var candidates: [MemoryPressureUnloadPolicy.Candidate] {
        [
            .init(id: recent, lastAccessedAt: now.addingTimeInterval(-60), type: .normal),
            .init(id: old, lastAccessedAt: now.addingTimeInterval(-3600), type: .normal),
            .init(id: oldPinned, lastAccessedAt: now.addingTimeInterval(-3600), type: .pinned),
            .init(id: neverUsed, lastAccessedAt: nil, type: .normal)
        ]
    }

    @Test func aWarningUnloadsRegularTabsLeftAloneForAWhile() {
        let unloaded = MemoryPressureUnloadPolicy.tabsToUnload(candidates, level: .warning, now: now)
        #expect(Set(unloaded) == [old, neverUsed])
    }

    @Test func criticalPressureUnloadsEveryBackgroundPage() {
        let unloaded = MemoryPressureUnloadPolicy.tabsToUnload(candidates, level: .critical, now: now)
        #expect(Set(unloaded) == [recent, old, oldPinned, neverUsed])
    }
}
