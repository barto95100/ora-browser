import Foundation

extension Tab {
    /// Records one visit per page shown. Title changes (e.g. "(3) Inbox") are
    /// not visits: they only update the entry's title.
    func recordVisit() {
        guard lastRecordedVisitURL != url else {
            updateHistoryTitle()
            return
        }
        lastRecordedVisitURL = url
        updateHistory()
    }

    func updateHistoryTitle() {
        // No space left (the tab is being deleted): nothing to record.
        guard let historyManager, let container = parentContainer else { return }
        let title = title
        let url = url
        Task { @MainActor in
            historyManager.updateTitle(title, for: url, container: container)
        }
    }
}
