import Foundation

/// Calls `completion` once: when `work` says it is done, or once `deadline`
/// has passed if it never does (then `onTimeout` first).
@MainActor
enum Deadline {
    static func run(
        _ deadline: Duration,
        work: (_ done: @escaping @MainActor () -> Void) -> Void,
        onTimeout: @escaping @MainActor () -> Void = {},
        completion: @escaping @MainActor () -> Void
    ) {
        let once = Once()
        work {
            guard once.claim() else { return }
            completion()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeInterval) {
            MainActor.assumeIsolated {
                guard once.claim() else { return }
                onTimeout()
                completion()
            }
        }
    }

    @MainActor
    private final class Once {
        private var isDone = false

        func claim() -> Bool {
            guard !isDone else { return false }
            isDone = true
            return true
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

extension BrowserPage {
    /// How long a page going away waits for its media to stop.
    static var mediaStopDeadline: Duration = .seconds(2)

    /// What stops a page's media: silence first (closing Picture in Picture
    /// is animated and takes a moment, during which the sound kept playing),
    /// then the page's elements emptied, then Picture in Picture closed.
    /// Replaced by tests: WebKit may never answer.
    typealias MediaStopSteps = @MainActor (BrowserPage, _ done: @escaping @MainActor () -> Void) -> Void

    static var stopMediaSteps: MediaStopSteps = { page, done in
        page.pauseAllMedia {
            page.evaluateJavaScript(stopMediaScript) { _, _ in
                page.closeMediaPresentations(completion: done)
            }
        }
    }

    /// Stops the page's media and its Picture in Picture before the page
    /// goes. Never waits more than `mediaStopDeadline`: WebKit could think a
    /// video was still in Picture in Picture with no window shown, never
    /// close it, and the tab never closed.
    func stopMedia(completion: @escaping @MainActor () -> Void) {
        Deadline.run(
            Self.mediaStopDeadline,
            work: { done in Self.stopMediaSteps(self, done) },
            onTimeout: { [weak self] in self?.log("media not stopped in time, closed anyway") },
            completion: completion
        )
    }

    private static let stopMediaScript = """
    document.querySelectorAll('video, audio').forEach(el => {
        try {
            el.pause();
            el.src = '';
            el.load();
        } catch (e) {}
    });
    """
}
