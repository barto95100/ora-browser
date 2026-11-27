import AppKit
import SwiftUI
@preconcurrency import WebKit

/// An installed extension's details in Settings › Extensions: where its
/// button is, its websites (like Safari's "Edit Websites"), its shortcuts
/// and its options.
@available(macOS 15.4, *)
struct ExtensionDetailView: View {
    let item: WebExtensionsManager.Installed
    @ObservedObject private var manager = WebExtensionsManager.shared
    /// What Ombre added to its copy (`ExtensionComplementPackage`), read once.
    @State private var added: ExtensionComplementPackage.Added?

    private var record: ExtensionRecord {
        item.record
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show next to the sidebar button", isOn: Binding(
                get: { record.isPinned },
                set: { manager.setPinned($0, id: record.id) }
            ))
            .help("Otherwise it is in the extensions menu (puzzle piece).")

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Allow in Private Browsing", isOn: Binding(
                    get: { record.allowsPrivateBrowsing },
                    set: { manager.setAllowsPrivateBrowsing($0, id: record.id) }
                ))
                Text("It could see what you do in private windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            userScripts

            websites

            refusedPermissions

            shortcuts

            complement

            if let context = item.context, context.optionsPageURL != nil {
                Button("Options…") { manager.openOptions(context) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: record.path) {
            let path = record.path
            added = record.bundleIdentifier == nil
                ? await Task.detached { ExtensionComplementPackage.added(at: path) }.value
                : nil
        }
    }

    // MARK: - Ombre's complement

    /// "Allow User Scripts", as in Chrome: for a copy that asks for them.
    @ViewBuilder private var userScripts: some View {
        if added?.apis.contains("userScripts") == true {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Allow User Scripts", isOn: Binding(
                    get: { record.allowsUserScripts },
                    set: { manager.setAllowsUserScripts($0, id: record.id) }
                ))
                Text(
                    // swiftlint:disable:next line_length
                    "It could run code it didn’t have reviewed, such as the scripts you add to it, on the websites it can read."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The APIs Ombre gives it that WebKit doesn't (`ExtensionComplements`).
    @ViewBuilder private var complement: some View {
        let apis = item.context.map {
            ExtensionComplementScript.permissions.intersection(
                ExtensionComplements.declaredPermissions(of: $0.webExtension).required
                    .union(ExtensionComplements.declaredPermissions(of: $0.webExtension).optional)
            ).sorted()
        } ?? []
        if let added {
            Text("Ombre added a complement to its copy, for: \(added.apis.formatted(.list(type: .and))).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !apis.isEmpty {
            Text("Ombre also gives it: \(apis.formatted(.list(type: .and))).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Websites

    private var websites: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Websites").font(.headline)
            let rules = ExtensionSiteAccess.activeRules(record.siteRules)
            if rules.isEmpty {
                Text("No website set yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(rules, id: \.host) { rule in
                HStack {
                    Text(rule.host)
                    if let expiresAt = rule.expiresAt {
                        Text("until \(expiresAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { rule.decision },
                        set: { manager.setSite(rule.host, $0, id: record.id) }
                    )) {
                        Text("Allow").tag(SiteDecision.allow)
                        Text("Don't Allow").tag(SiteDecision.deny)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        manager.setSite(rule.host, .ask, id: record.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Forget (asked again next time)")
                }
            }
            HStack {
                Text("Other websites")
                Spacer()
                Picker("", selection: Binding(
                    get: { record.otherSites },
                    set: { manager.setOtherSites($0, id: record.id) }
                )) {
                    Text("Ask").tag(SiteDecision.ask)
                    Text("Allow").tag(SiteDecision.allow)
                    Text("Don't Allow").tag(SiteDecision.deny)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: - Refused permissions

    /// What was refused when it asked: not asked again, until forgotten.
    @ViewBuilder private var refusedPermissions: some View {
        if !record.deniedPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Refused Permissions").font(.headline)
                Text("Not asked again until forgotten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(record.deniedPermissions, id: \.self) { name in
                    HStack {
                        Text(ExtensionPermissionText.describe(name))
                        Spacer()
                        Button {
                            manager.forgetRefusedPermission(name, id: record.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Forget (asked again next time)")
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts

    @ViewBuilder private var shortcuts: some View {
        let commands = (item.context?.commands ?? []).filter { WebExtensionsManager.display($0) != nil }
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard Shortcuts").font(.headline)
                ForEach(commands, id: \.id) { command in
                    HStack {
                        Text(command.title)
                        Spacer()
                        Text(WebExtensionsManager.display(command) ?? "")
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }
                Text("Ombre's own shortcuts come first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One line under the extension's name.
    static func summary(of record: ExtensionRecord) -> String {
        let other = switch record.otherSites {
        case .ask: String(localized: "Asks on each website")
        case .allow: String(localized: "All websites")
        case .deny: String(localized: "No website")
        }
        let count = ExtensionSiteAccess.activeRules(record.siteRules).count
        return count == 0 ? other : "\(other) · " + String(localized: "\(count) sites set")
    }
}
