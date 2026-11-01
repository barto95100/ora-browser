import AppKit
@testable import Ora
import Testing

@MainActor
struct DefaultBrowserManagerTests {
    private final class FakeSystem: @unchecked Sendable {
        var defaultBrowserID: String?
        var pendingCompletion: (@Sendable () -> Void)?
        var setRequests = 0

        init(defaultBrowserID: String?) {
            self.defaultBrowserID = defaultBrowserID
        }
    }

    private let ownID = "com.example.browser"

    private func makeManager(
        _ system: FakeSystem,
        center: NotificationCenter = NotificationCenter()
    ) -> DefaultBrowserManager {
        DefaultBrowserManager(
            defaultBrowserBundleID: { system.defaultBrowserID },
            ownBundleID: ownID,
            setAsDefault: { completion in
                system.setRequests += 1
                system.pendingCompletion = completion
            },
            notificationCenter: center
        )
    }

    @Test func comparesBundleIdentifiersIgnoringCase() {
        #expect(DefaultBrowserManager.isDefault(defaultBrowserID: "com.example.browser", ownBundleID: ownID))
        #expect(DefaultBrowserManager.isDefault(defaultBrowserID: "COM.Example.Browser", ownBundleID: ownID))
        #expect(!DefaultBrowserManager.isDefault(defaultBrowserID: "com.apple.Safari", ownBundleID: ownID))
        #expect(!DefaultBrowserManager.isDefault(defaultBrowserID: nil, ownBundleID: ownID))
        #expect(!DefaultBrowserManager.isDefault(defaultBrowserID: ownID, ownBundleID: nil))
    }

    @Test func statusIsCorrectRightAfterLaunch() {
        #expect(makeManager(FakeSystem(defaultBrowserID: ownID)).isDefault)
        #expect(!makeManager(FakeSystem(defaultBrowserID: "com.apple.Safari")).isDefault)
    }

    @Test func refreshPicksUpAChange() {
        let system = FakeSystem(defaultBrowserID: "com.apple.Safari")
        let manager = makeManager(system)
        system.defaultBrowserID = ownID
        #expect(!manager.isDefault)
        manager.refresh()
        #expect(manager.isDefault)
    }

    @Test func becomingActiveRefreshesTheStatus() {
        let system = FakeSystem(defaultBrowserID: ownID)
        let center = NotificationCenter()
        let manager = makeManager(system, center: center)
        system.defaultBrowserID = "com.apple.Safari"
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(!manager.isDefault)
    }

    @Test func otherNotificationsDoNotRefresh() {
        let system = FakeSystem(defaultBrowserID: ownID)
        let center = NotificationCenter()
        let manager = makeManager(system, center: center)
        system.defaultBrowserID = "com.apple.Safari"
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(manager.isDefault)
    }

    @Test func setAsDefaultRefreshesWhenTheRequestCompletes() async {
        let system = FakeSystem(defaultBrowserID: "com.apple.Safari")
        let manager = makeManager(system)
        manager.requestSetAsDefault()
        #expect(system.setRequests == 1)
        system.defaultBrowserID = ownID
        system.pendingCompletion?()
        await waitUntil { manager.isDefault }
        #expect(manager.isDefault)
    }

    @Test func declinedRequestKeepsTheStatus() async {
        let system = FakeSystem(defaultBrowserID: "com.apple.Safari")
        let manager = makeManager(system)
        manager.requestSetAsDefault()
        system.pendingCompletion?()
        await Task.yield()
        #expect(!manager.isDefault)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
    }
}
