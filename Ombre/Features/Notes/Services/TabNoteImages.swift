import Foundation

/// An image added to a tab's note from outside its panel (a capture of the
/// element picker). The panel, if open, saves its text first and reads the
/// note again after.
@MainActor
enum TabNoteImages {
    /// Posted with the tab's identifier (`object`) before the note changes.
    static let willChange = Notification.Name("TabNoteImages.willChange")
    /// Posted with the tab's identifier (`object`) after.
    static let didChange = Notification.Name("TabNoteImages.didChange")

    /// Whether it was added. Never for a private tab: private windows keep no notes.
    @discardableResult
    static func add(_ png: Data, from tab: Tab, link: URL?, store: NotesStore = .shared) -> Bool {
        guard !tab.isPrivate else { return false }
        NotificationCenter.default.post(name: willChange, object: tab.id)
        let space = tab.container
        let folder = store.folder(for: space.id, named: space.name)
        guard let note = store.tabNote(for: tab.id, in: folder)
            ?? store.createTabNote(for: tab.id, title: tab.title, pageURL: tab.url, in: folder),
            let path = store.saveImage(png, in: folder)
        else { return false }
        let line = NoteMarkdown.imageLine(alt: String(tab.title.prefix(40)), path: path, link: link)
        store.write(NoteMarkdown.appending(line, to: store.read(note)), to: note)
        NotificationCenter.default.post(name: didChange, object: tab.id)
        return true
    }
}
