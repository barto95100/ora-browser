import Foundation

extension TabManager {
    /// Gives `tab` the name typed (an empty one goes back to the page's
    /// title, see `TabName`), saved with the tab; in a private window, in
    /// memory only like the rest of it.
    func renameTab(_ tab: Tab, to typed: String) {
        let before = tab.customName
        tab.rename(to: typed)
        guard tab.customName != before else { return }
        modelContext.saveOrLog("rename tab")
    }
}
