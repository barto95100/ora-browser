import AppKit
@testable import Ombre
import Testing

/// Bounded snapshots, caches and lists (PERF-14, PERF-15, INT-19).
struct SmallPerfTests {
    private struct Item {
        let name: String
        let date: Date?
    }

    /// Never used tabs go last: they used to count as used just now.
    @Test func theSwitcherShowsTheMostRecentTabs() {
        let now = Date()
        let items = [
            Item(name: "never", date: nil),
            Item(name: "old", date: now.addingTimeInterval(-600)),
            Item(name: "new", date: now),
            Item(name: "older", date: now.addingTimeInterval(-6000))
        ]
        let shown = TabSwitcherStart.mostRecent(items, accessedAt: \.date, limit: 3).map(\.name)
        #expect(shown == ["new", "old", "older"])
    }

    /// Another revision of a list replaces the cached one, never another list's.
    @Test func aNewRevisionReplacesTheCachedRuleLists() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ContentBlockerArtifactStore(baseURL: folder)
        let prefix = AppIdentity.identifier("adblock")
        let cached = ["\(prefix).easylist.r1.0", "\(prefix).easylist.r1.1", "\(prefix).other.r1.0", "static.trackers"]
        let replaced = store.replacedRuleLists(cached, by: "\(prefix).easylist.r2.0")
        #expect(Set(replaced) == ["\(prefix).easylist.r1.0", "\(prefix).easylist.r1.1"])
        #expect(store.replacedRuleLists(cached, by: "\(prefix).easylist.r1.2").isEmpty)
        #expect(store.replacedRuleLists(cached, by: "static.trackers").isEmpty)
    }

    /// A site's largest icon is kept at 32 points.
    @Test func aLargeFaviconIsDownscaled() throws {
        let large = NSImage(size: NSSize(width: 512, height: 256), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let small = large.downscaled(toFit: 32)
        #expect(small.size == NSSize(width: 32, height: 16))
        let bitmap = try #require(small.representations.first as? NSBitmapImageRep)
        #expect(bitmap.pixelsWide == 64)
        let tiny = NSImage(size: NSSize(width: 16, height: 16))
        #expect(tiny.downscaled(toFit: 32) === tiny)
    }

    /// A tab without a page answers at once: the switcher used to wait for
    /// it forever, then took no snapshot any more.
    @MainActor
    @Test func aTabWithoutAPageAnswersASnapshotAtOnce() async throws {
        try await TabManagerTestWindow.run { window in
            let tab = try window.addUnloadedTab("unloaded", order: 1, in: window.activeSpace)
            #expect(tab.browserPage == nil)
            var answered = false
            tab.takeSnapshot(configuration: .full) { image, _ in
                #expect(image == nil)
                answered = true
            }
            #expect(answered)
        }
    }
}
