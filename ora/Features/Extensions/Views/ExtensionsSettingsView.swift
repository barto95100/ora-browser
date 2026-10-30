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
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { manager.refreshCandidates() }
        .sheet(item: $review) { review in
            ExtensionReviewSheet(review: review) {
                manager.install(review)
                self.review = nil
            } cancel: {
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.record.name)
                if let appName = item.record.appName {
                    Text("From \(appName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Websites: " + ExtensionPermissionText.describeSites(item.record.grantedMatchPatterns)
                    .joined(separator: ", "))
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
private struct ExtensionReviewSheet: View {
    let review: WebExtensionsManager.Review
    let add: () -> Void
    let cancel: () -> Void

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
                        "From \(review.candidate.appName)"
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

            if review.permissions.contains("nativeMessaging") {
                Text("Talking to its app (such as Touch ID unlock) only works in Safari.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add Extension", action: add)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
