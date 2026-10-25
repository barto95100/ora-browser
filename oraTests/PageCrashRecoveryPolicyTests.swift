import Foundation
@testable import Ora
import Testing

struct PageCrashRecoveryPolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func visiblePageReloadsRightAway() {
        var policy = PageCrashRecoveryPolicy()

        let action = policy.processDidTerminate(isVisible: true, now: start)

        #expect(action == .reloadNow)
        #expect(!policy.isPendingReload)
    }

    @Test func backgroundPageReloadsOnlyOnceShown() {
        var policy = PageCrashRecoveryPolicy()

        let action = policy.processDidTerminate(isVisible: false, now: start)
        #expect(action == .reloadWhenShown)
        #expect(policy.isPendingReload)

        let reloadsWhenShown = policy.tabDidBecomeVisible(now: start.addingTimeInterval(600))
        #expect(reloadsWhenShown)
        #expect(!policy.isPendingReload)

        let reloadsAgain = policy.tabDidBecomeVisible(now: start.addingTimeInterval(601))
        #expect(!reloadsAgain)
    }

    @Test func showingATabThatDidNotCrashDoesNothing() {
        var policy = PageCrashRecoveryPolicy()

        let reloads = policy.tabDidBecomeVisible(now: start)

        #expect(!reloads)
    }

    @Test func crashSoonAfterAnAutomaticReloadStopsReloading() {
        var policy = PageCrashRecoveryPolicy()
        _ = policy.processDidTerminate(isVisible: true, now: start)

        let action = policy.processDidTerminate(isVisible: true, now: start.addingTimeInterval(5))

        #expect(action == .showCrashPage)
    }

    @Test func crashLongAfterAReloadReloadsAgain() {
        var policy = PageCrashRecoveryPolicy()
        _ = policy.processDidTerminate(isVisible: true, now: start)

        let later = start.addingTimeInterval(PageCrashRecoveryPolicy.repeatedCrashInterval + 1)

        let action = policy.processDidTerminate(isVisible: true, now: later)

        #expect(action == .reloadNow)
    }

    @Test func backgroundCrashSoonAfterAReloadShowsTheCrashPage() {
        var policy = PageCrashRecoveryPolicy()
        _ = policy.processDidTerminate(isVisible: false, now: start)
        _ = policy.tabDidBecomeVisible(now: start)

        let action = policy.processDidTerminate(isVisible: false, now: start.addingTimeInterval(10))

        #expect(action == .showCrashPage)
        #expect(!policy.isPendingReload)
    }

    @Test func crashSoonAfterTryAgainShowsTheCrashPageAgain() {
        var policy = PageCrashRecoveryPolicy()
        policy.recordReload(at: start)

        let action = policy.processDidTerminate(isVisible: true, now: start.addingTimeInterval(3))

        #expect(action == .showCrashPage)
    }
}
