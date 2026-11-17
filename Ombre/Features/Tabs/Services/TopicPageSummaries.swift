import Foundation

/// The descriptions loaded pages give of themselves (meta description, or
/// og:description), for the subject grouping. Pages already loaded only:
/// nothing is fetched. Read in the app's script world.
@MainActor
enum TopicPageSummaries {
    /// All the pages' answers are waited for that long at most.
    static let wait: Duration = .seconds(1)

    /// Cut in the page too: a huge one never comes to the app.
    private static let script = """
    (() => {
        const content = (selector) => {
            const meta = document.querySelector(selector);
            return meta ? String(meta.content || '').trim() : '';
        };
        return (content('meta[name="description" i]') || content('meta[property="og:description" i]'))
            .slice(0, 1000);
    })()
    """ // not shown

    /// The loaded web pages of `tabs`, by tab: what `read` reads.
    static func pages(of tabs: [Tab]) -> [(id: UUID, page: BrowserPage)] {
        tabs.compactMap { tab in
            guard let page = tab.browserPage, tab.isWebViewReady,
                  ["http", "https"].contains(tab.url.scheme?.lowercased() ?? "")
            else { return nil }
            return (tab.id, page)
        }
    }

    /// The descriptions of `pages`, by tab, empty ones left out.
    static func read(_ pages: [(id: UUID, page: BrowserPage)]) async -> [UUID: String] {
        guard !pages.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            let gathering = Gathering(continuation, expected: pages.count)
            for (id, page) in pages {
                page.evaluateJavaScript(script) { value, _ in
                    MainActor.assumeIsolated { gathering.add(id, value as? String) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: wait)
                gathering.finish()
            }
        }
    }

    /// The answers as they come; given once, all in or at the deadline.
    @MainActor
    private final class Gathering {
        private var continuation: CheckedContinuation<[UUID: String], Never>?
        private var summaries: [UUID: String] = [:]
        private var left: Int

        init(_ continuation: CheckedContinuation<[UUID: String], Never>, expected: Int) {
            self.continuation = continuation
            left = expected
        }

        func add(_ id: UUID, _ summary: String?) {
            if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summaries[id] = summary
            }
            left -= 1
            if left == 0 { finish() }
        }

        func finish() {
            continuation?.resume(returning: summaries)
            continuation = nil
        }
    }
}
