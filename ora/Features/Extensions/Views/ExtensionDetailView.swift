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

            websites

            shortcuts

            if let context = item.context, context.optionsPageURL != nil {
                Button("Options…") { manager.openOptions(context) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Ora's own shortcuts come first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One line under the extension's name.
    static func summary(of record: ExtensionRecord) -> String {
        let other = switch record.otherSites {
        case .ask: "Asks on each website"
        case .allow: "All websites"
        case .deny: "No website"
        }
        let count = ExtensionSiteAccess.activeRules(record.siteRules).count
        return count == 0 ? other : "\(other) · \(count) set"
    }
}
