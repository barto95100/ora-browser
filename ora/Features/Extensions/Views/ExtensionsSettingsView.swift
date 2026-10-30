import AppKit
import SwiftUI
@preconcurrency import WebKit

/// Settings › Extensions: the Safari extensions of installed apps, like Safari.
struct ExtensionsSettingsView: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            ExtensionsSettingsContent()
        } else {
            SettingsCard(header: "Extensions") {
                Text("Extensions need macOS 15.4 or later.")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionsSettingsContent: View {
    @ObservedObject private var manager = WebExtensionsManager.shared
    @State private var review: WebExtensionsManager.Review?
    @State private var reviewError: String?
    @State private var pendingRemoval: WebExtensionsManager.Installed?
    @State private var fileError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard(header: "Installed") {
                    if manager.installed.isEmpty {
                        Text("No extensions yet. Add one from your apps below.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(manager.installed) { item in
                                InstalledExtensionRow(item: item) { pendingRemoval = item }
                            }
                        }
                    }
                }

                SettingsCard(
                    header: "From Your Apps",
                    description: "Apps from the App Store can bring Safari extensions. Ora runs them like Safari."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(manager.candidates) { candidate in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.appURL.path))
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                    Text("From \(candidate.appName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add…") { open(candidate) }
                            }
                        }
                        if manager.candidates.isEmpty {
                            Text("No other extension found in your apps.")
                                .foregroundStyle(.secondary)
                        }
                        if let reviewError {
                            Label(reviewError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("More Extensions on the App Store…") {
                            if let url = WebExtensionsManager.appStoreURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                SettingsCard(
                    header: "Other Extensions",
                    description: "On an extension's page in the Chrome Web Store, click “Add to Ora”. "
                        + "Some Chrome extensions use features WebKit doesn't have: they may not work fully."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Add from Folder or Zip…") { chooseFile() }
                            Button(manager.isCheckingUpdates ? "Checking…" : "Check for Updates") {
                                #if DEBUG
                                    // ⌥-click: reinstalls the current versions (to test updates).
                                    let reinstall = NSEvent.modifierFlags.contains(.option)
                                #else
                                    let reinstall = false
                                #endif
                                Task { await manager.checkForUpdates(reinstall: reinstall) }
                            }
                            .disabled(manager.isCheckingUpdates)
                        }
                        Text(manager.updateStatus ?? "Updates are checked once a day, like Chrome.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let fileError {
                            Label(fileError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { manager.refreshCandidates() }
        .sheet(item: $review) { review in
            ExtensionReviewSheet(review: review) { allowAllSites in
                manager.install(review, allowAllSites: allowAllSites)
                self.review = nil
            } cancel: {
                manager.discard(review)
                self.review = nil
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.record.name ?? "")”?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { item in
            Button("Remove", role: .destructive) { manager.remove(id: item.id) }
        } message: { _ in
            Text("Its data in Ora is deleted. The app that brings it stays installed.")
        }
    }

    private func chooseFile() {
        fileError = nil
        guard let url = WebExtensionsManager.chooseExtensionFile() else { return }
        Task {
            do {
                review = try await manager.reviewFile(at: url)
            } catch {
                fileError = "Ora couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func open(_ candidate: SafariExtensionCandidate) {
        reviewError = nil
        Task {
            do {
                review = try await manager.review(candidate)
            } catch {
                reviewError = "Ora couldn't read \(candidate.name): \(error.localizedDescription)"
            }
        }
    }
}

@available(macOS 15.4, *)
private struct InstalledExtensionRow: View {
    let item: WebExtensionsManager.Installed
    let remove: () -> Void
    @ObservedObject private var manager = WebExtensionsManager.shared

    @State private var showsDetails = false
    @State private var reviewsUpdate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row
            if let pending = manager.pendingUpdates[item.id] {
                HStack(spacing: 8) {
                    Label("Version \(pending.version) asks for more.", systemImage: "arrow.down.circle")
                        .font(.caption)
                    Button("Review…") { reviewsUpdate = true }
                        .controlSize(.small)
                }
                .padding(.leading, 38)
                .sheet(isPresented: $reviewsUpdate) {
                    ExtensionUpdateSheet(name: item.record.name, update: pending) {
                        manager.acceptUpdate(id: item.id)
                        reviewsUpdate = false
                    } notNow: {
                        manager.declineUpdate(id: item.id)
                        reviewsUpdate = false
                    }
                }
            }
            DisclosureGroup("Details", isExpanded: $showsDetails) {
                ExtensionDetailView(item: item)
                    .padding(.top, 6)
            }
            .padding(.leading, 38)
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.record.name)
                Text(item.record.originText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ExtensionDetailView.summary(of: item.record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error = item.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { item.record.isEnabled },
                set: { manager.setEnabled($0, id: item.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = item.context?.webExtension.icon(for: CGSize(width: 28, height: 28)) {
            Image(nsImage: image).resizable()
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}

/// What an extension asks for, before adding it.
@available(macOS 15.4, *)
struct ExtensionReviewSheet: View {
    let review: WebExtensionsManager.Review
    let add: (_ allowAllSites: Bool) -> Void
    let cancel: () -> Void
    /// Like Safari: each website is asked the first time.
    @State private var allowAllSites = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let image = review.webExtension.icon(for: CGSize(width: 40, height: 40)) {
                    Image(nsImage: image).resizable().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add “\(review.name)”?")
                        .font(.title3.weight(.semibold))
                    Text([
                        review.webExtension.displayVersion.map { "Version \($0)" },
                        review.originText
                    ]
                    .compactMap(\.self).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }
            if let description = review.webExtension.displayDescription {
                Text(description)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("It will be able to:").font(.headline)
                ForEach(review.permissions, id: \.self) { permission in
                    Label(ExtensionPermissionText.describe(permission), systemImage: "checkmark")
                }
                Label(
                    "Read and change pages on: "
                        + ExtensionPermissionText.describeSites(review.sites).joined(separator: ", "),
                    systemImage: "globe"
                )
            }

            if !review.sites.isEmpty {
                Picker("Websites:", selection: $allowAllSites) {
                    Text("Ask on each website").tag(false)
                    Text("Allow on all websites").tag(true)
                }
                .pickerStyle(.radioGroup)
                Text("Password managers need all websites to fill in your logins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if review.permissions.contains("nativeMessaging") {
                Text("Talking to its app (such as Touch ID unlock) only works in Safari.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Extension") { add(allowAllSites) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// An update that asks for more than what was allowed: shown before it
/// runs (like Chrome).
@available(macOS 15.4, *)
private struct ExtensionUpdateSheet: View {
    let name: String
    let update: WebExtensionsManager.PendingUpdate
    let accept: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update “\(name)” to version \(update.version)?")
                .font(.title3.weight(.semibold))
            Text("This version asks for more than what you allowed:")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(update.newPermissions, id: \.self) { permission in
                    Label(ExtensionPermissionText.describe(permission), systemImage: "plus.circle")
                }
                if !update.newSites.isEmpty {
                    Label(
                        "Read and change pages on: "
                            + ExtensionPermissionText.describeSites(update.newSites).joined(separator: ", "),
                        systemImage: "globe"
                    )
                }
            }
            Text("Until then, the current version keeps running.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now", action: notNow)
                    .keyboardShortcut(.cancelAction)
                Button("Update", action: accept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
