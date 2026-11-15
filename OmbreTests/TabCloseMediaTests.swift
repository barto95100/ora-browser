import Foundation
@testable import Ombre
import Testing

/// `Deadline`: what closing a page waits for, bounded.
@MainActor
struct DeadlineTests {
    @MainActor
    private final class Calls {
        var completions = 0
        var timeouts = 0
    }

    @Test func workDoneInTimeCompletesOnceWithoutTimeout() async throws {
        let calls = Calls()
        Deadline.run(
            .milliseconds(100),
            work: { done in
                done()
                done()
            },
            onTimeout: { calls.timeouts += 1 },
            completion: { calls.completions += 1 }
        )
        try await Task.sleep(for: .milliseconds(300))
        #expect(calls.completions == 1)
        #expect(calls.timeouts == 0)
    }

    @Test func workNeverDoneCompletesAtTheDeadline() async throws {
        let calls = Calls()
        var keptDone: (@MainActor () -> Void)?
        Deadline.run(
            .milliseconds(100),
            work: { done in keptDone = done },
            onTimeout: { calls.timeouts += 1 },
            completion: { calls.completions += 1 }
        )
        #expect(calls.completions == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(calls.completions == 1)
        #expect(calls.timeouts == 1)
        // Done after the deadline: nothing more.
        keptDone?()
        #expect(calls.completions == 1)
    }
}

extension TabManagerTests {
    /// The tab's close button always closes it, even when WebKit never says
    /// its media stopped (a video it thinks is still in Picture in Picture,
    /// with no window shown): the tab stayed, and each later click on its
    /// close button was ignored as a close already under way.
    @MainActor
    @Suite(.serialized)
    struct CloseWithStuckMedia {
        private func withStuckMedia(_ body: () async throws -> Void) async rethrows {
            let steps = BrowserPage.stopMediaSteps
            let deadline = BrowserPage.mediaStopDeadline
            BrowserPage.stopMediaSteps = { _, _ in }
            BrowserPage.mediaStopDeadline = .milliseconds(200)
            defer {
                BrowserPage.stopMediaSteps = steps
                BrowserPage.mediaStopDeadline = deadline
            }
            try await body()
        }

        @Test func aNormalTabIsDeleted() async throws {
            try await withStuckMedia {
                try await TabManagerTestWindow.run { window in
                    let tab = try await window.openLoaded("video")
                    window.tabManager.closeTab(tab: tab)
                    await window.waitUntil("tab deleted", timeout: .seconds(5)) { window.isDeleted(tab) }
                }
            }
        }

        @Test func aPinnedTabLosesItsPageAndCanBeClosedAgain() async throws {
            try await withStuckMedia {
                try await TabManagerTestWindow.run { window in
                    let tab = try await window.openLoaded("video")
                    tab.type = .pinned
                    window.tabManager.closeTab(tab: tab)
                    await window.waitUntil("page destroyed", timeout: .seconds(5)) {
                        tab.browserPage == nil && !tab.isClosing
                    }
                    #expect(!window.isDeleted(tab))
                }
            }
        }
    }
}
