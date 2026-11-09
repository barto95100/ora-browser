import AppKit
import SwiftUI

/// Imports spaces from another browser (Zen for now): choose its profile, see
/// what it holds, pick the spaces, import.
struct BrowserImportSheet: View {
    @EnvironmentObject private var tabManager: TabManager
    @Environment(\.dismiss) private var dismiss

    @State private var profile: URL?
    @State private var data: ImportedBrowserData?
    @State private var selected: Set<Int> = []
    @State private var failure: String?
    @State private var importedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from Zen")
                .font(.title2.weight(.semibold))

            if let importedCount {
                done(importedCount)
            } else if let data {
                preview(data)
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
                "Ombre imports your spaces with their Essentials (as favorites), pinned tabs and folders. Open tabs are not imported."
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("Quit Zen first, so its latest changes are saved.")
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
                Button("Choose Zen Profile…") { chooseProfile() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func preview(_ data: ImportedBrowserData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile {
                Text("Profile: \(ZenImporter.profileName(profile))")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(data.spaces.enumerated()), id: \.offset) { index, space in
                    Toggle(isOn: binding(for: index)) {
                        HStack(spacing: 8) {
                            Text(space.emoji ?? "•")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                Text(Self.summary(of: space))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Text("Spaces whose name is already used get “(Zen)” after their name.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Other Profile…") { chooseProfile() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { runImport(data) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
    }

    private func done(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                String(localized: "\(count) spaces imported."),
                systemImage: "checkmark.circle.fill"
            )
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
                if isOn { selected.insert(index) } else { selected.remove(index) }
            }
        )
    }

    private func chooseProfile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = ZenImporter.profilesFolder
        panel.message = String(
            localized: "Choose your Zen profile folder, or the Profiles folder to use the latest profile."
        )
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        load(folder)
    }

    private func load(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        guard let profile = ZenImporter.profile(in: folder) else {
            failure = String(localized: "No Zen session in this folder. Choose a profile in Zen's Profiles folder.")
            return
        }
        do {
            let read = try ZenImporter.read(profile: profile)
            guard !read.isEmpty else {
                failure = String(localized: "This profile has no Essentials, pinned tabs or folders to import.")
                data = nil
                return
            }
            failure = nil
            self.profile = profile
            data = read
            selected = Set(read.spaces.indices)
        } catch {
            failure = String(localized: "Ombre couldn't read this Zen session.")
            data = nil
        }
    }

    private func runImport(_ data: ImportedBrowserData) {
        let spaces = data.spaces.enumerated().filter { selected.contains($0.offset) }.map(\.element)
        tabManager.importSpaces(ImportedBrowserData(spaces: spaces), from: "Zen") // no translation: the browser's name
        importedCount = spaces.count
    }

    static func summary(of space: ImportedSpace) -> String {
        let tabs = ImportedPinnedItem.tabCount(in: space.pinned)
        let folders = ImportedPinnedItem.folderCount(in: space.pinned)
        return [
            String(localized: "\(space.favorites.count) favorites"),
            String(localized: "\(tabs) pinned tabs"),
            String(localized: "\(folders) folders")
        ].joined(separator: " · ")
    }
}
