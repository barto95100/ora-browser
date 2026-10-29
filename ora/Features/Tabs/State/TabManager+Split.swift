import AppKit
import Foundation

/// Split View, like Arc: two tabs of a space side by side (see `TabSplits`),
/// pinned and favorite tabs included. The focused side is the active tab: the
/// URL bar and the shortcuts act on it.
extension TabManager {
    /// Left tab → right tab, for the tabs of `container`.
    func splitPairs(in container: TabContainer) -> [UUID: UUID] {
        TabSplits.pairs(container.tabs.map { TabSplits.Entry(id: $0.id, rightID: $0.splitRightTabID) })
    }

    /// Splits of `container` shown by a row of the normal tabs, keyed by the
    /// normal tab that holds the row: the left one when both are normal (the
    /// right one is then hidden), the normal one otherwise. A split of two
    /// pinned or favorite tabs has no row: each stays in its section.
    func splitRows(in container: TabContainer) -> (rows: [UUID: (left: Tab, right: Tab)], hidden: Set<UUID>) {
        let tabsByID = Dictionary(container.tabs.map { ($0.id, $0) }) { first, _ in first }
        var rows: [UUID: (left: Tab, right: Tab)] = [:]
        var hidden = Set<UUID>()
        for (leftID, rightID) in splitPairs(in: container) {
            guard let left = tabsByID[leftID], let right = tabsByID[rightID] else { continue }
            if left.type == .normal {
                rows[left.id] = (left, right)
                if right.type == .normal { hidden.insert(right.id) }
            } else if right.type == .normal {
                rows[right.id] = (left, right)
            }
        }
        return (rows, hidden)
    }

    /// The two tabs of the split `tab` is in, if any.
    func split(containing tab: Tab) -> (left: Tab, right: Tab)? {
        let pairs = splitPairs(in: tab.container)
        guard let partnerID = TabSplits.partner(of: tab.id, in: pairs),
              let partner = tab.container.tabs.first(where: { $0.id == partnerID })
        else { return nil }
        return pairs[tab.id] == partnerID ? (tab, partner) : (partner, tab)
    }

    func splitPartner(of tab: Tab) -> Tab? {
        guard let split = split(containing: tab) else { return nil }
        return split.left.id == tab.id ? split.right : split.left
    }

    /// The tabs a window shows when `tab` is active: it, and its split partner.
    func shownTabs(around tab: Tab?) -> [Tab] {
        guard let tab else { return [] }
        return [tab] + (splitPartner(of: tab).map { [$0] } ?? [])
    }

    /// Whether the window shows `tab` (active, or beside the active tab).
    func isShown(_ tab: Tab) -> Bool {
        shownTabs(around: activeTab).contains { $0.id == tab.id }
    }

    /// Whether `tab` can be shown beside the active tab.
    func canOpenInSplitView(_ tab: Tab) -> Bool {
        guard let active = activeTab else { return false }
        return active.id != tab.id
            && active.container.id == tab.container.id
            && splitPartner(of: active)?.id != tab.id
    }

    /// Shows `tab` at the right of the active tab, and focuses it.
    func openInSplitView(_ tab: Tab) {
        guard canOpenInSplitView(tab) else { return }
        openInSplitView(tab, on: .right)
    }

    /// A tab dropped on one side of the page: shown on that side, beside the
    /// active tab (it replaces the other side of a split), and focused.
    func openInSplitView(_ tab: Tab, on side: SplitDropSide) {
        guard let active = activeTab, active.id != tab.id, active.container.id == tab.container.id else { return }
        switch side {
        case .left: pairInSplit(tab, with: active)
        case .right: pairInSplit(active, with: tab)
        }
        activateTab(tab)
    }

    /// Separates the split `tab` is in: the right tab comes back under the left
    /// one when both are in the same section.
    func separateSplit(containing tab: Tab, save: Bool = true) {
        guard let split = split(containing: tab) else { return }
        split.left.splitRightTabID = nil
        if split.left.type == split.right.type {
            split.left.container.placeTab(split.right, after: split.left)
        }
        if save { try? modelContext.save() }
    }

    /// ⌃⇧= (New Split View): the next tab opened from the launcher goes at the
    /// right of the active tab. Returns false when the active tab cannot be split.
    func prepareNewSplit() -> Bool {
        guard let active = activeTab else { return false }
        pendingSplitLeftTabID = active.id
        return true
    }

    /// Puts `newTab` at the right of the tab New Split View was asked from.
    func completePendingSplit(with newTab: Tab) {
        guard let leftID = pendingSplitLeftTabID else { return }
        pendingSplitLeftTabID = nil
        guard let left = newTab.container.tabs.first(where: { $0.id == leftID }), left.id != newTab.id
        else { return }
        pairInSplit(left, with: newTab)
    }

    func saveSplitLayout() {
        try? modelContext.save()
    }

    /// Loads a tab's page if it is not loaded (the other side of a split).
    func loadIfNeeded(_ tab: Tab) {
        guard !tab.isWebViewReady else { return }
        tab.restoreTransientState(
            historyManager: tab.historyManager ?? historyManager,
            downloadManager: tab.downloadManager ?? downloadManager,
            tabManager: self,
            isPrivate: tab.isPrivate
        )
    }

    /// Auto Picture in Picture on tab switch: pages leaving the window go to
    /// PiP, pages coming back leave it. Both sides of a split are shown, so
    /// moving between them changes nothing.
    func togglePiPOnSwitch(to tab: Tab) {
        guard SettingsStore.shared.autoPiPEnabled else { return }
        let leaving = shownTabs(around: activeTab)
        let coming = shownTabs(around: tab)
        for page in coming where !leaving.contains(where: { $0.id == page.id }) {
            page.evaluateJavaScript("window.__oraTriggerPiP(true)")
        }
        for page in leaving where !coming.contains(where: { $0.id == page.id }) {
            page.evaluateJavaScript("window.__oraTriggerPiP()")
        }
    }

    /// Focusing the other side of a split from the sidebar also moves the
    /// keyboard focus, so typing goes to the focused page.
    func focusPageIfSplit(_ tab: Tab, previous: Tab?) {
        guard let previous, splitPartner(of: tab)?.id == previous.id else { return }
        DispatchQueue.main.async {
            guard let webView = tab.browserPage?.webView, let window = webView.window else { return }
            window.makeFirstResponder(webView)
        }
    }

    private func pairInSplit(_ left: Tab, with right: Tab) {
        separateSplit(containing: left, save: false)
        separateSplit(containing: right, save: false)
        left.splitRightTabID = right.id
        left.splitFraction = 0.5
        loadIfNeeded(left)
        loadIfNeeded(right)
        try? modelContext.save()
    }
}

/// Side of the page a tab is dropped on to make a split.
enum SplitDropSide {
    case left
    case right
}
