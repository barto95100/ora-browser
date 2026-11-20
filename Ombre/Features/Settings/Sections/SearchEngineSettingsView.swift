import AppKit
import SwiftData
import SwiftUI

/// Settings › Search: the engine and the AI for all spaces, then every
/// engine (search, then AI) with its keywords, whether it shows, and the
/// custom ones to add, change or remove.
struct SearchEngineSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var preferences = SearchEnginePreferences.shared
    @StateObject private var service = SearchEngineService()
    @Query(sort: TabContainer.displayOrder) private var spaces: [TabContainer]
    @Environment(\.theme) private var theme

    /// The engine being changed or added, in a sheet.
    @State private var editing: SearchEngineEditor.Subject?

    var body: some View {
        // Once per update, for every row.
        let rules = service.rules
        SettingsSection {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15))
                    .foregroundStyle(.tint)
                Text("Type a keyword then Tab in the address bar to search that site directly or ask that AI.")
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            defaultsCard(rules)

            engineCard(
                header: String(localized: "Search Engines"),
                engines: rules.engines.filter { !$0.isAIChat },
                rules: rules
            )
            engineCard(
                header: String(localized: "settings.search.ai", defaultValue: "AI"),
                engines: rules.engines.filter(\.isAIChat),
                rules: rules
            )

            HStack {
                Spacer()
                Button {
                    editing = .new
                } label: {
                    Label("Add Custom Engine…", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { subject in
            SearchEngineEditor(subject: subject, service: service, spaces: spaces)
        }
    }

    // MARK: - Defaults

    private func defaultsCard(_ rules: SearchEngineRules) -> some View {
        SettingsCard(
            header: String(localized: "Defaults"),
            description: String(localized: "For spaces that don’t choose their own, in Settings › Spaces.")
        ) {
            SettingsRow(title: String(localized: "Search Engine")) {
                Picker("", selection: Binding(
                    get: { rules.defaultSearchName },
                    set: { settings.globalDefaultSearchEngine = $0 == SearchEngineRules.fallbackSearch ? nil : $0 }
                )) {
                    ForEach(
                        rules.engines.filter { !$0.isAIChat || $0.name == rules.defaultSearchName },
                        id: \.name
                    ) { engine in
                        Text(engine.name).tag(engine.name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingsRow(title: String(localized: "settings.search.ai", defaultValue: "AI")) {
                Picker("", selection: Binding(
                    get: { rules.defaultAIName },
                    set: { preferences.globalAI = $0 == SearchEnginePreferences.fallbackAI ? nil : $0 }
                )) {
                    ForEach(rules.engines.filter(\.isAIChat), id: \.name) { engine in
                        Text(engine.name).tag(engine.name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    // MARK: - Engines

    private func engineCard(header: String, engines: [SearchEngine], rules: SearchEngineRules) -> some View {
        SettingsCard(header: header) {
            ForEach(Array(engines.enumerated()), id: \.element.name) { index, engine in
                if index > 0 { Divider() }
                engineRow(engine, rules: rules)
            }
        }
    }

    private func engineRow(_ engine: SearchEngine, rules: SearchEngineRules) -> some View {
        let custom = settings.customSearchEngines.first { $0.name == engine.name }
        let isDefault = rules.isDefault(engine.name)
        let isLocked = rules.isLocked(engine.name)
        return HStack(spacing: 12) {
            SearchEngineIcon(engine: engine, favicon: custom?.favicon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(engine.name)
                    if isDefault {
                        Text("Default")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(theme.accent.opacity(0.18)))
                            .foregroundStyle(theme.accent)
                    }
                    if custom != nil {
                        Text("Custom")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                KeywordChips(keywords: engine.aliases)
            }
            Spacer(minLength: 8)
            Button {
                editing = custom.map { .custom($0) } ?? .builtIn(engine.name)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(custom == nil ? String(localized: "Edit Keywords…") : String(localized: "Edit Engine…"))
            .accessibilityLabel(
                custom == nil ? String(localized: "Edit Keywords…") : String(localized: "Edit Engine…")
            )
            Toggle("", isOn: Binding(
                get: { isLocked || preferences.isChosenShown(engine.name) },
                set: { preferences.setShown($0, engine.name) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(isLocked)
            .help(isLocked
                ? String(localized: "Used by default or by a space: always shown.")
                : String(localized: "Show in the address bar, with its keywords."))
            .accessibilityLabel(String(localized: "Show \(engine.name)"))
        }
        .padding(.vertical, 1)
    }
}

/// An engine's keywords, as small tags.
private struct KeywordChips: View {
    let keywords: [String]

    var body: some View {
        if keywords.isEmpty {
            Text("No keyword")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                ForEach(keywords.prefix(6), id: \.self) { word in
                    Text(word)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                if keywords.count > 6 {
                    Text(verbatim: "+\(keywords.count - 6)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Keywords: \(keywords.joined(separator: ", "))"))
        }
    }
}

/// An engine's logo, its site's icon (custom engines) or its initial.
struct SearchEngineIcon: View {
    let engine: SearchEngine
    var favicon: NSImage?

    /// Logos in color, shown as they are on white; the others are one
    /// color, drawn in white on the engine's color.
    private static let colorLogos: Set<String> = [
        "Google", "DuckDuckGo", "Kagi", "Bing", "T3Chat", "Gemini" // no translation
    ]
    /// Logos that do not draw here: their initial.
    private static let initialOnly: Set<String> = ["Copilot", "GitHub Copilot"] // no translation

    var body: some View {
        Group {
            if !engine.icon.isEmpty, Self.colorLogos.contains(engine.name) {
                Image(engine.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white))
            } else if !engine.icon.isEmpty, !Self.initialOnly.contains(engine.name) {
                Image(engine.icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(engine.foregroundColor ?? .white)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(engine.color))
            } else if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white))
            } else {
                Text(String(engine.name.first ?? "?"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(engine.color))
            }
        }
        .frame(width: 24, height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
