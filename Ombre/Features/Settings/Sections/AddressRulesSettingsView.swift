import SwiftData
import SwiftUI

/// Settings › Address Rules: "this address → this space" (`AddressRule`),
/// a new rule, and an address to test.
struct AddressRulesSettingsView: View {
    @Query(sort: TabContainer.displayOrder) private var spaces: [TabContainer]
    @ObservedObject private var settings = SettingsStore.shared
    @State private var newPattern = ""
    @State private var newIncludesSubdomains = true
    @State private var newSpaceID: UUID?
    @State private var testAddress = ""

    private var spaceIDs: Set<UUID> {
        Set(spaces.map(\.id))
    }

    /// The rules of the spaces that exist (a deleted space's are removed).
    private var rules: [AddressRule] {
        settings.addressRules.filter { spaceIDs.contains($0.spaceID) }
    }

    var body: some View {
        SettingsSection {
            SettingsCard(
                header: String(localized: "Address Rules"),
                description: String(localized: """
                Links from other apps, and the new tabs a page opens, go to the space of the rule for their \
                address; the most precise rule wins. Not for addresses you type, links in the same tab, \
                or private windows.
                """)
            ) {
                if rules.isEmpty {
                    Text("No rules yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                        if rule.id != rules.last?.id { Divider() }
                    }
                }
            }

            SettingsCard(header: String(localized: "New Rule")) {
                newRuleForm
            }

            SettingsCard(header: String(localized: "Test an Address")) {
                TextField(String(localized: "https://…"), text: $testAddress)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text("Test an Address"))
                if !testAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(testResult)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Rules

    private func ruleRow(_ rule: AddressRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.display)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rule.kind.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("", selection: spaceBinding(for: rule)) {
                ForEach(spaces) { space in
                    Text(space.name).tag(space.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Text("Space"))
            Button {
                settings.addressRules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Rule")
            .accessibilityLabel(Text("Delete Rule"))
        }
    }

    private func spaceBinding(for rule: AddressRule) -> Binding<UUID> {
        Binding(
            get: { rule.spaceID },
            set: { spaceID in
                guard let index = settings.addressRules.firstIndex(where: { $0.id == rule.id }) else { return }
                settings.addressRules[index].spaceID = spaceID
            }
        )
    }

    // MARK: - New rule

    /// The space chosen for a new rule; a space deleted meanwhile: the first.
    private var newRuleSpaceID: UUID? {
        let chosen = newSpaceID.flatMap { id in spaces.contains { $0.id == id } ? id : nil }
        return chosen ?? spaces.first?.id
    }

    private var newRule: AddressRule? {
        guard let spaceID = newRuleSpaceID else { return nil }
        return AddressRule.parse(newPattern, includesSubdomains: newIncludesSubdomains, spaceID: spaceID)
    }

    @ViewBuilder
    private var newRuleForm: some View {
        HStack(spacing: 10) {
            TextField(String(localized: "*.example.com, example.com or example.com/page"), text: $newPattern)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addRule)
                .accessibilityLabel(Text("Address"))
            Picker("", selection: Binding(get: { newRuleSpaceID }, set: { newSpaceID = $0 })) {
                ForEach(spaces) { space in
                    Text(space.name).tag(Optional(space.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Text("Space"))
            Button("Add", action: addRule)
                .disabled(newRule == nil)
        }
        Toggle("Include Subdomains", isOn: $newIncludesSubdomains)
            // A prefix, or `*.` typed: the kind is given.
            .disabled(newRule?.kind == .prefix || newPattern.trimmingCharacters(in: .whitespaces).hasPrefix("*."))
        if let newRule {
            Text(String(localized: "Adds \(newRule.display) (\(newRule.kind.title))."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func addRule() {
        guard let rule = newRule else { return }
        settings.addressRules = AddressRule.adding(rule, to: settings.addressRules)
        newPattern = ""
    }

    // MARK: - Test

    private var testResult: String {
        guard let url = AddressRulesTester.url(from: testAddress) else {
            return String(localized: "Not a web address.")
        }
        guard let rule = AddressRule.rule(for: url, in: rules, spaceIDs: spaceIDs),
              let space = spaces.first(where: { $0.id == rule.spaceID })
        else {
            return String(localized: "No rule: the link opens in the space it comes from.")
        }
        return String(localized: "\(rule.display) → \(space.name)")
    }
}

/// What the test field reads: an address, `https://` added when missing.
enum AddressRulesTester {
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }
}
