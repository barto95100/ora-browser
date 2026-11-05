import Foundation

extension TabManager {
    /// The tab's state in this window, made when first asked for.
    func runtime(for tab: Tab) -> TabRuntime {
        if let runtime = runtimes[tab.id] { return runtime }
        let runtime = TabRuntime()
        runtimes[tab.id] = runtime
        return runtime
    }

    /// The tab's state in this window if it has one, without making one.
    func existingRuntime(for tabID: UUID) -> TabRuntime? {
        runtimes[tabID]
    }

    /// The tab left the window (deleted): its state too. A page unloaded or
    /// rebuilt keeps its runtime, reset, since the page's view watches it.
    func dropRuntime(for tabID: UUID) {
        runtimes[tabID] = nil
    }
}
