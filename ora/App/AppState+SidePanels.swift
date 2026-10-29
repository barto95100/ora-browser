import Foundation

/// The side panels and their large counterparts, from the menus and buttons.
extension AppState {
    /// The tab's note beside the page, or all the notes without a page.
    func toggleTabNote(hasPage: Bool) {
        if hasPage {
            showTabNote.toggle()
        } else {
            showLauncher = false
            showHistory = false
            showTime = false
            showNotes.toggle()
        }
    }
}

extension AppState {
    /// The summary beside the page, or the large panel without a page.
    func toggleTimeSummary(hasPage: Bool) {
        if hasPage {
            showTimeSummary.toggle()
        } else {
            showLauncher = false
            showHistory = false
            showNotes = false
            showTime.toggle()
        }
    }
}
