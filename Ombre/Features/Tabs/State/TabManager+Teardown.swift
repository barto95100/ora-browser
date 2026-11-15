import Foundation
import SwiftData

extension TabManager {
    /// The window closes: nothing of it keeps running, and its pages go (with,
    /// for a private window, their private website data). Called once the
    /// window is closing (see `OmbreRoot`); doing it twice does nothing more.
    func tearDown() {
        isTornDown = true
        TabCleaner.shared.unregister(self)
        stopSyncingWithOtherWindows()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        if let peek {
            silence(peek.page)
            closePeek()
        }
        let tabs = (try? modelContext.fetch(FetchDescriptor<Tab>())) ?? []
        for tab in tabs {
            guard let page = tab.browserPage else { continue }
            silence(page)
            tab.destroyWebView()
        }
        for tab in tabs {
            tab.pageRuntime = nil
        }
        runtimes.removeAll()
        runtimeTabs.removeAll()
        // What was not saved yet (title, URL of in-page navigations…).
        modelContext.saveOrLog("close window")
    }

    /// The app quits: what was not saved yet is.
    func saveOnQuit() {
        modelContext.saveOrLog("quit")
    }

    /// Stops a page's media and its Picture in Picture before it goes: a video
    /// still playing went to a black Picture in Picture that kept the closed
    /// window alive. The same steps as closing a tab (`BrowserPage.stopMedia`),
    /// all sent at once, before the page is torn down (they would otherwise
    /// reach a page already out of the window); the page stays alive until
    /// Picture in Picture has closed, or `mediaStopDeadline` at most.
    private func silence(_ page: BrowserPage) {
        page.pauseAllMedia {}
        page.evaluateJavaScript(BrowserPage.stopMediaScript)
        Deadline.run(
            BrowserPage.mediaStopDeadline,
            work: { done in page.closeMediaPresentations { done() } },
            completion: { withExtendedLifetime(page) {} }
        )
    }
}
