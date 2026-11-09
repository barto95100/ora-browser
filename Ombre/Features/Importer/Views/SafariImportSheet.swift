import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports Safari's export (File › Export Browsing Data): one space per
/// profile, with its history, and the bookmarks in the space chosen.
struct SafariImportSheet: View {
    @EnvironmentObject private var tabManager: TabManager
    @Environment(\.dismiss) private var dismiss

    @State private var export: SafariImporter.Export?
    @State private var selected: Set<Int> = []
    /// The profile whose space gets the bookmarks; nil: none.
    @State private var bookmarksIn: Int?
    /// "Don't import the bookmarks" was chosen (not just no profile left).
    @State private var bookmarksDeclined = false
    @State private var failure: String?
    @State private var importedCount: Int?
    @State private var isReading = false

    /// The default profile's space.
    private static let defaultSpaceName = "Safari" // no translation: the browser's name

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from Safari")
                .font(.title2.weight(.semibold))

            if let importedCount {
                done(importedCount)
            } else if let export {
                preview(export)
            } else if isReading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the export…")
                }
            } else {
                start
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Steps

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                // swiftlint:disable:next line_length
                "In Safari, choose File › Export Browsing Data to File, then choose the exported file here. Each Safari profile becomes a space with its history, and your bookmarks become pinned tabs."
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("Passwords are not imported. The export stays where it is: Ombre only reads it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Export…") { chooseExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func preview(_ export: SafariImporter.Export) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(export.profiles.enumerated()), id: \.offset) { index, profile in
                    Toggle(isOn: binding(for: index)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name ?? Self.defaultSpaceName)
                            Text(String(localized: "\(profile.history.count) pages in the history"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if export.bookmarkCount > 0 {
                Picker(String(localized: "\(export.bookmarkCount) bookmarks go to:"), selection: Binding(
                    get: { bookmarksIn },
                    set: { bookmarksIn = $0
                        bookmarksDeclined = $0 == nil
                    }
                )) {
                    ForEach(selected.sorted(), id: \.self) { index in
                        Text(export.profiles[index].name ?? Self.defaultSpaceName).tag(Int?.some(index))
                    }
                    Text("Don't import the bookmarks").tag(Int?.none)
                }
            }

            Text("Spaces whose name is already used get “(Safari)” after their name.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Other Export…") { chooseExport() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { runImport(export) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
    }

    private func done(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "\(count) spaces imported."), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Find them in the space switcher at the bottom of the sidebar.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { selected.contains(index) },
            set: { isOn in
                if isOn {
                    selected.insert(index)
                    // The bookmarks had lost their space with the last profile unchecked.
                    if bookmarksIn == nil, !bookmarksDeclined { bookmarksIn = index }
                } else {
                    selected.remove(index)
                    // The bookmarks follow a space that is still imported.
                    if bookmarksIn == index { bookmarksIn = selected.min() }
                }
            }
        )
    }

    private func chooseExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = String(localized: "Choose the file Safari exported (a .zip), or the folder it unpacked to.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    /// Read off the main thread (a large export takes a moment); the file's
    /// access stays open until the reading is done.
    private func load(_ url: URL) {
        isReading = true
        failure = nil
        export = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SafariImporter.Export, Error> in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return Result {
                    let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    return isFolder
                        ? try SafariImporter.read(folder: url)
                        : try SafariImporter.read(archive: Data(contentsOf: url, options: .mappedIfSafe))
                }
            }.value
            isReading = false
            switch result {
            case let .success(read):
                export = read
                selected = Set(read.profiles.indices)
                bookmarksIn = read.profiles.isEmpty ? nil : 0
                bookmarksDeclined = false
            case .failure(SafariImporter.Failure.nothingToImport):
                failure = String(localized: "This export has no history or bookmarks Ombre can import.")
            case .failure:
                failure = String(localized: "Ombre couldn't read this export. Choose the .zip file Safari made.")
            }
        }
    }

    private func runImport(_ export: SafariImporter.Export) {
        let data = export.spaces(
            profiles: Array(selected),
            bookmarksIn: bookmarksIn,
            defaultName: Self.defaultSpaceName
        )
        tabManager.importSpaces(data, from: "Safari") // no translation: the browser's name
        importedCount = data.spaces.count
    }
}
