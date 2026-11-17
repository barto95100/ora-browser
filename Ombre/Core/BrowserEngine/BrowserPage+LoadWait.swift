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
