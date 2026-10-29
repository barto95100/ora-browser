import AppKit
import SwiftUI

/// The space's notes, over the page like the history: Markdown files (see
/// `NotesStore`), edited or read, with checkboxes (`- [ ] …`) and images.
struct NotesPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var privacyMode: PrivacyMode
    @Environment(\.theme) private var theme
    @Environment(\.window) private var window

    @State private var folder: URL?
    @State private var notes: [Note] = []
    @State private var selected: Note?
    @State private var text = ""
    @State private var titleDraft = ""
    @State private var isEditing = false
    @State private var query = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var noteToDelete: Note?
    @State private var escapeMonitor: Any?
    @State private var pasteMonitor: Any?
    @State private var isDropTargeted = false

    private let store = NotesStore.shared

    private var shownNotes: [Note] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 230)
                Divider().opacity(0.5)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.accent, lineWidth: 2)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: NoteImageImport.dropTypes, isTargeted: $isDropTargeted) { providers in
                        NoteImageImport.load(providers, completion: addImage)
                    }
            }
            .frame(maxWidth: 920, maxHeight: 640)
            .background(theme.launcherMainBackground)
            .background(BlurEffectView(material: .popover, blendingMode: .withinWindow))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.foreground.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 40, x: 0, y: 24)
            .padding(.top, 60)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            load()
            watchEscape()
            pasteMonitor = NoteImageImport.watchPaste(in: window, isActive: { true }, paste: addImage)
        }
        .onDisappear {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            pasteMonitor = nil
        }
        .onChange(of: text) { scheduleSave() }
        // Links of a note open in a new tab.
        .environment(\.openURL, OpenURLAction { url in
            tabManager.openTab(url: url, historyManager: historyManager, isPrivate: privacyMode.isPrivate)
            close()
            return .handled
        })
        .confirmationDialog(
            "Move \"\(noteToDelete?.title ?? "")\" to the Trash?",
            isPresented: Binding(get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } }),
            presenting: noteToDelete
        ) { note in
            Button("Move to Trash", role: .destructive) { delete(note) }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New Note")
            }

            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(shownNotes) { note in
                        noteRow(note)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                if let folder { store.showInFinder(folder) }
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.mutedForeground)
        }
        .padding(12)
    }

    private func noteRow(_ note: Note) -> some View {
        let isSelected = selected?.url == note.url
        return Button {
            open(note)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(note.modifiedAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? theme.mutedBackground : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Move to Trash…") { noteToDelete = note }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let selected {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .semibold))
                        .onSubmit(renameSelected)
                    NoteAddImageMenu(add: addImage)
                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "eye" : "pencil")
                    }
                    .buttonStyle(.plain)
                    .help(isEditing ? "Read" : "Edit")
                    Button {
                        noteToDelete = selected
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Move to Trash")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().opacity(0.5)
                if isEditing {
                    NoteTextEditor(text: $text)
                        .padding(14)
                } else {
                    NoteReaderView(
                        markdown: text,
                        folder: folder,
                        openPage: openPageInPeek,
                        onToggleTask: { line in text = NoteMarkdown.togglingTask(atLine: line, in: text) }
                    )
                }
            }
        } else {
            VStack(spacing: 12) {
                Text("No note yet")
                    .foregroundColor(theme.mutedForeground)
                OraButton(label: "New Note", action: newNote)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func load() {
        guard let space = tabManager.activeContainer else { return }
        let folder = store.folder(for: space.id, named: space.name)
        self.folder = folder
        notes = store.notes(in: folder)
        if let first = notes.first {
            open(first)
        }
    }

    private func open(_ note: Note, editing: Bool? = nil) {
        saveNow()
        selected = note
        titleDraft = note.title
        text = store.read(note)
        isEditing = editing ?? text.isEmpty
    }

    /// Escape closes, wherever the focus is (nothing has it while reading).
    private func watchEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53,
                  event.window === (window ?? NSApp.keyWindow),
                  noteToDelete == nil
            else { return event }
            close()
            return nil
        }
    }

    /// An image added at the end of the note (a new one if none is open).
    private func addImage(_ png: Data) {
        // A note started by an image shows it; otherwise the mode stays.
        let isNewNote = selected == nil
        if isNewNote { newNote() }
        guard let folder, selected != nil, let path = store.saveImage(png, in: folder) else { return }
        text = NoteMarkdown.appending(NoteMarkdown.imageLine(alt: "", path: path), to: text)
        if isNewNote { isEditing = false }
        saveNow()
    }

    /// The page of a capture, over the current tab (Peek).
    private func openPageInPeek(_ url: URL) {
        guard let tab = tabManager.activeTab else {
            tabManager.openTab(url: url, historyManager: historyManager, isPrivate: privacyMode.isPrivate)
            close()
            return
        }
        close()
        tab.openPeek(url)
    }

    private func newNote() {
        guard let folder, let note = store.create(in: folder) else { return }
        notes = store.notes(in: folder)
        open(note, editing: true)
    }

    private func renameSelected() {
        guard let selected, let folder else { return }
        saveNow()
        let renamed = store.rename(selected, to: titleDraft)
        self.selected = renamed
        titleDraft = renamed.title
        notes = store.notes(in: folder)
    }

    private func delete(_ note: Note) {
        guard let folder else { return }
        if selected?.url == note.url {
            saveTask?.cancel()
            selected = nil
            text = ""
        }
        store.delete(note)
        notes = store.notes(in: folder)
        if selected == nil, let first = notes.first {
            open(first)
        }
    }

    /// Saved half a second after the last change, and when leaving the note.
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
        guard let selected, store.read(selected) != text else { return }
        store.write(text, to: selected)
    }

    private func close() {
        saveNow()
        if titleDraft != selected?.title { renameSelected() }
        appState.showNotes = false
    }
}
