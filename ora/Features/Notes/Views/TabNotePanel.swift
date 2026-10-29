import AppKit
import SwiftUI

/// The note of a tab, beside its page: text, links, tasks and captures of
/// the page. A Markdown file of the space's notes (see `NotesStore`), so it
/// is in the notes panel and the Finder too.
struct TabNotePanel: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @Environment(\.theme) private var theme
    @Environment(\.window) private var window

    @State private var folder: URL?
    @State private var note: Note?
    @State private var text = ""
    @State private var isEditing = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isCapturing = false
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?

    private let store = NotesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if note != nil {
                if isEditing {
                    NoteTextEditor(text: $text)
                        .padding(10)
                } else {
                    NoteReaderView(
                        markdown: text,
                        folder: folder,
                        openPage: { tab.openPeek($0) },
                        onToggleTask: { line in text = NoteMarkdown.togglingTask(atLine: line, in: text) }
                    )
                }
            } else {
                emptyState
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.border).frame(width: 1)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accent, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        // Screenshots of the user: dropped or pasted (mouse over the note, or
        // typing in it — never a paste meant for the page).
        .onDrop(of: NoteImageImport.dropTypes, isTargeted: $isDropTargeted) { providers in
            NoteImageImport.load(providers, completion: addImage)
        }
        .onHover { isHovering = $0 }
        .onAppear {
            load()
            pasteMonitor = NoteImageImport.watchPaste(
                in: window,
                isActive: { isHovering || NoteImageImport.isEditingNoteText(in: window) },
                paste: addImage
            )
        }
        .onDisappear {
            saveNow()
            appState.areaCapture = nil
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        // Another tab: the note follows it.
        .onChange(of: tab.id) {
            saveNow()
            appState.areaCapture = nil
            load()
        }
        .onChange(of: text) { scheduleSave() }
        // Links of the note open in a new tab, the note stays.
        .environment(\.openURL, OpenURLAction { url in
            tabManager.openTab(url: url, historyManager: historyManager, isPrivate: false)
            return .handled
        })
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note?.title ?? "Tab Note")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(tab.title)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: captureVisible) {
                Image(systemName: "camera.viewfinder")
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .help("Capture the Visible Page")
            Button(action: captureArea) {
                Image(systemName: "rectangle.dashed")
            }
            .buttonStyle(.plain)
            .help("Capture an Area of the Page")
            NoteAddImageMenu(add: addImage)
            if note != nil {
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "eye" : "pencil")
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Read" : "Edit")
            }
            Button {
                appState.showLauncher = false
                appState.showHistory = false
                appState.showTime = false
                appState.showNotes = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("All Notes of the Space (⌥⌘N)")
            Button {
                appState.showTabNote = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .foregroundColor(theme.foreground.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No note for this tab yet")
                .foregroundColor(theme.mutedForeground)
            Text("Drop or paste a screenshot to start one")
                .font(.system(size: 11))
                .foregroundColor(theme.mutedForeground.opacity(0.8))
            OraButton(label: "New Note", action: createNote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func load() {
        let space = tab.container
        let folder = store.folder(for: space.id, named: space.name)
        self.folder = folder
        note = store.tabNote(for: tab.id, in: folder)
        text = note.map(store.read) ?? ""
        isEditing = false
    }

    private func createNote() {
        guard let folder,
              let created = store.createTabNote(for: tab.id, title: tab.title, pageURL: tab.url, in: folder)
        else { return }
        note = created
        text = store.read(created)
        isEditing = true
    }

    /// The part of the page on screen, added at the end of the note.
    private func captureVisible() {
        isCapturing = true
        let page = tab.url
        tab.takeSnapshot(configuration: .full) { image, _ in
            isCapturing = false
            guard let png = image.flatMap(NoteImageImport.pngData(fromSnapshot:)) else { return }
            // The words at the middle of the screen: the page opens there.
            tab.evaluateJavaScript(PageAnchor.wordsScript(at: nil)) { result, _ in
                addImage(png, from: tab, link: PageAnchor.url(page, scrolledTo: result as? String ?? ""))
            }
        }
    }

    /// An area traced over the page (or the other page of a split).
    private func captureArea() {
        appState.areaCapture = AreaCaptureRequest(tabID: tab.id) { png, captured, link in
            addImage(png, from: captured, link: link)
        }
    }

    /// An image at the end of the note; a capture keeps the page it shows.
    private func addImage(_ png: Data, from page: Tab?, link: URL?) {
        // A note started by an image shows it; otherwise the mode stays.
        let isNewNote = note == nil
        if isNewNote { createNote() }
        guard let folder, note != nil, let path = store.saveImage(png, in: folder) else { return }
        let alt = page.map { String($0.title.prefix(40)) } ?? ""
        text = NoteMarkdown.appending(NoteMarkdown.imageLine(alt: alt, path: path, link: link), to: text)
        if isNewNote { isEditing = false }
        saveNow()
    }

    private func addImage(_ png: Data) {
        addImage(png, from: nil, link: nil)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard let note, store.read(note) != text else { return }
        store.write(text, to: note)
    }
}
