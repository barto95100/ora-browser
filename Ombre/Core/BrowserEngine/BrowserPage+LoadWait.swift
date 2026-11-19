import Foundation
@preconcurrency import WebKit

extension BrowserPage {
    /// Waits until the page has loaded (`hasLoaded`), `limit` at most:
    /// told by WebKit (its address and loading state), never polled.
    /// Whether it loaded.
    func waitUntilLoaded(within limit: Duration) async -> Bool {
        if hasLoaded { return true }
        return await withCheckedContinuation { continuation in
            let wait = LoadWait(continuation)
            let check: @MainActor @Sendable (BrowserPage) -> Void = { page in
                if page.hasLoaded { wait.finish(true) }
            }
            wait.observations = [
                webView.observe(\.isLoading) { [weak self] _, _ in self?.notifyOnMain(check) },
                webView.observe(\.url) { [weak self] _, _ in self?.notifyOnMain(check) }
            ]
            wait.timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                wait.finish(false)
            }
        }
    }
}

/// A page at one moment, to tell what happened since: a load started, or
/// its address changed without one (a page changing its own address).
struct NavigationMark: Equatable {
    let loadStarts: Int
    let url: URL?
}

/// How a wait for a navigation ended.
enum NavigationWaitEnd: Equatable {
    /// A navigation started after the mark and is over.
    case loaded
    /// None started after the mark, nor within the grace period.
    case none
    /// One started but was still loading at the limit.
    case stillLoading
}

extension BrowserPage {
    /// The page now.
    var navigationMark: NavigationMark {
        NavigationMark(loadStarts: loadStarts, url: webView.url)
    }

    /// Whether a navigation started since `mark`, or one is under way.
    func hasNavigated(since mark: NavigationMark) -> Bool {
        loadStarts > mark.loadStarts || webView.url != mark.url || isLoading || !hasLoaded
    }

    /// Waits for the navigation started since `mark`, or starting within
    /// `grace` (a click's link may start loading a moment after the click),
    /// to end: `limit` at most in all. Told by WebKit (its loading state and
    /// address), never polled; the timers only end the wait.
    func waitForNavigation(
        since mark: NavigationMark,
        grace: Duration,
        within limit: Duration
    ) async -> NavigationWaitEnd {
        let state: @MainActor @Sendable (BrowserPage) -> NavigationWaitEnd? = { page in
            guard page.hasNavigated(since: mark) else { return nil }
            return page.hasLoaded ? .loaded : .stillLoading
        }
        if state(self) == .loaded { return .loaded }
        return await withCheckedContinuation { continuation in
            let wait = NavigationWait(continuation)
            let check: @MainActor @Sendable (BrowserPage) -> Void = { page in
                if state(page) == .loaded { wait.finish(.loaded) }
            }
            wait.observations = [
                webView.observe(\.isLoading) { [weak self] _, _ in self?.notifyOnMain(check) },
                webView.observe(\.url) { [weak self] _, _ in self?.notifyOnMain(check) }
            ]
            wait.timers = [
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: grace)
                    // Nothing started meanwhile: nothing to wait for.
                    if let self, state(self) == nil { wait.finish(.none) }
                },
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: limit)
                    wait.finish(self.flatMap(state) ?? .none)
                }
            ]
        }
    }
}

/// One wait for a navigation: answered once, its observers then dropped.
@MainActor
private final class NavigationWait {
    private var continuation: CheckedContinuation<NavigationWaitEnd, Never>?
    var observations: [NSKeyValueObservation] = []
    var timers: [Task<Void, Never>] = []

    init(_ continuation: CheckedContinuation<NavigationWaitEnd, Never>) {
        self.continuation = continuation
    }

    func finish(_ end: NavigationWaitEnd) {
        guard let continuation else { return }
        self.continuation = nil
        observations.forEach { $0.invalidate() }
        observations = []
        timers.forEach { $0.cancel() }
        continuation.resume(returning: end)
    }
}

/// One wait for a page's load: answered once, its observers then dropped.
@MainActor
private final class LoadWait {
    private var continuation: CheckedContinuation<Bool, Never>?
    var observations: [NSKeyValueObservation] = []
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ loaded: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        observations.forEach { $0.invalidate() }
        observations = []
        timer?.cancel()
        continuation.resume(returning: loaded)
    }
}
