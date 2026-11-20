import AppKit
import SwiftUI

/// Changes an engine: a built-in one's keywords, or all of a custom engine
/// (name, address, keywords, search or AI); also adds one.
struct SearchEngineEditor: View {
    enum Subject: Identifiable {
        case new
        case builtIn(String)
        case custom(CustomSearchEngine)

        var id: String {
            switch self {
            case .new: return "new"
            case let .builtIn(name): return "builtIn.\(name)"
            case let .custom(engine): return "custom.\(engine.id)"
            }
        }
    }

    let subject: Subject
    let service: SearchEngineService
    let spaces: [TabContainer]

    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var keywordsText = ""
    @State private var isAI = false
    @State private var acceptsQuery = true
    /// The address last opened by Test: its question shows until it changes.
    @State private var testedTemplate: String?
    @State private var isConfirmingDelete = false

    /// What stands for the search in an address.
    private static let searchToken = "%s" // no translation
    private static let queryToken = "{query}" // no translation

    /// The search sent by Test.
    private static let testQuery = "Ombre" // no translation

    private var builtIn: SearchEngine? {
        guard case let .builtIn(name) = subject else { return nil }
        return service.builtInSearchEngines.first { $0.name == name }
    }

    private var existingCustom: CustomSearchEngine? {
        guard case let .custom(engine) = subject else { return nil }
        return engine
    }

    /// The engine's name as kept now (before a rename).
    private var currentName: String? {
        builtIn?.name ?? existingCustom?.name
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var template: String {
        SearchEngineRules.template(from: address)
    }

    private var keywords: [String] {
        SearchEngineRules.keywords(from: keywordsText)
    }

    private var conflicts: [String: String] {
        service.rules.conflicts(of: keywords, for: currentName ?? trimmedName)
    }

    private var nameError: String? {
        guard builtIn == nil, !trimmedName.isEmpty else { return nil }
        let taken = service.searchEngines.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame && $0.name != currentName
        }
        return taken ? String(localized: "Another engine already has this name.") : nil
    }

    private var addressError: String? {
        guard builtIn == nil, !address.isEmpty, !SearchEngineService.isValidTemplate(template) else { return nil }
        return String(
            localized: "The address must start with https:// or http:// and contain \(Self.searchToken) or \(Self.queryToken)."
        )
    }

    private var conflictError: String? {
        guard let (word, other) = conflicts.sorted(by: { $0.key < $1.key }).first else { return nil }
        return String(localized: "“\(word)” is already a keyword of \(other).")
    }

    private var canSave: Bool {
        if builtIn != nil { return conflictError == nil }
        return !trimmedName.isEmpty && SearchEngineService.isValidTemplate(template)
            && nameError == nil && conflictError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if builtIn == nil { customFields }
            keywordsField
            footer
        }
        .padding(22)
        .frame(width: 480)
        .onAppear(perform: load)
        .confirmationDialog(
            "Remove “\(existingCustom?.name ?? "")”?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text("Spaces that use it go back to the global choice.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let builtIn {
                SearchEngineIcon(engine: builtIn)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var title: String {
        if let builtIn { return builtIn.name }
        return existingCustom == nil ? String(localized: "Add Custom Engine") : String(localized: "Edit Engine")
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Type", selection: $isAI) {
                Text("Search Engine").tag(false)
                Text(String(localized: "settings.search.ai", defaultValue: "AI")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            field(String(localized: "Name")) {
                TextField("", text: $name, prompt: Text(isAI ? "Mistral" : "Wikipedia"))
                    .textFieldStyle(.roundedBorder)
                error(nameError)
            }

            field(String(localized: "Address")) {
                HStack {
                    TextField("", text: $address, prompt: Text(verbatim: "https://example.com/search?q=%s"))
                        .textFieldStyle(.roundedBorder)
                    Button("Test") { test() }
                        .disabled(!SearchEngineService.isValidTemplate(template))
                        .help(String(localized: "Opens a test search in a browser window."))
                }
                Text("Put \(Self.searchToken) (or \(Self.queryToken)) where the search goes. For example:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(verbatim: "https://fr.wikipedia.org/w/index.php?search=%s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                error(addressError)
            }

            queryInAddressField
        }
    }

    /// Whether the site reads the search from its address; after Test, a
    /// question to set it from what the page showed.
    private var queryInAddressField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("The site receives the question from the address", isOn: $acceptsQuery)
                .toggleStyle(.checkbox)
                // Chosen by hand: the question after Test is answered.
                .onChange(of: acceptsQuery) { testedTemplate = nil }
            Text("Otherwise, Ombre opens the site and copies the question: paste it with ⌘V.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if testedTemplate == template {
                HStack(spacing: 8) {
                    Text("Did “\(Self.testQuery)” appear in the site’s field or results?")
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Yes") { answerTest(appeared: true) }
                    Button("No") { answerTest(appeared: false) }
                }
                .controlSize(.small)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func answerTest(appeared: Bool) {
        acceptsQuery = appeared
        testedTemplate = nil
    }

    private var keywordsField: some View {
        field(String(localized: "Keywords")) {
            TextField("", text: $keywordsText, prompt: Text(verbatim: "wp, wiki"))
                .textFieldStyle(.roundedBorder)
            Text("Separated by commas. Type one then Tab in the address bar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            error(conflictError)
        }
    }

    private var footer: some View {
        HStack {
            if existingCustom != nil {
                Button("Remove…", role: .destructive) { isConfirmingDelete = true }
            } else if let builtIn, keywords != builtIn.aliases {
                Button("Restore Keywords") { keywordsText = builtIn.aliases.joined(separator: ", ") }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            content()
        }
    }

    @ViewBuilder
    private func error(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func load() {
        switch subject {
        case .new:
            break
        case let .builtIn(engineName):
            let own = builtIn?.aliases ?? []
            keywordsText = service.preferences.keywords(of: engineName, own: own).joined(separator: ", ")
        case let .custom(engine):
            name = engine.name
            address = engine.searchURL
            keywordsText = engine.aliases.joined(separator: ", ")
            isAI = engine.isAIChat
            acceptsQuery = engine.acceptsQueryInAddress
        }
    }

    func test() {
        guard let url = SearchEngineService.searchURL(template: template, query: Self.testQuery),
              let window = BrowserWindows.front
        else { return }
        NotificationCenter.default.post(name: .openURL, object: window, userInfo: ["url": url])
        window.makeKeyAndOrderFront(nil)
        testedTemplate = template
    }

    private func save() {
        guard canSave else { return }
        if let builtIn {
            service.preferences.setKeywords(keywords == builtIn.aliases ? nil : keywords, for: builtIn.name)
        } else if let existing = existingCustom {
            let changed = CustomSearchEngine(
                id: existing.id,
                name: trimmedName,
                searchURL: template,
                aliases: keywords,
                faviconData: existing.searchURL == template ? existing.faviconData : nil,
                faviconBackgroundColorData: existing.searchURL == template
                    ? existing.faviconBackgroundColorData : nil,
                isAIChat: isAI,
                acceptsQueryInAddress: acceptsQuery
            )
            settings.updateCustomSearchEngine(changed)
            if existing.isAIChat != isAI { dropChoices(of: existing.name, asAI: existing.isAIChat) }
            if existing.name != trimmedName { rename(existing.name, to: trimmedName) }
            if existing.searchURL != template { refreshIcon(of: changed) }
        } else {
            CustomSearchEngine.createWithFavicon(
                name: trimmedName,
                searchURL: template,
                aliases: keywords,
                isAIChat: isAI,
                acceptsQueryInAddress: acceptsQuery
            ) { [weak settings] engine in
                settings?.addCustomSearchEngine(engine)
            }
        }
        dismiss()
    }

    /// The icon of the new address's site.
    private func refreshIcon(of engine: CustomSearchEngine) {
        CustomSearchEngine.createWithFavicon(
            id: engine.id,
            name: engine.name,
            searchURL: engine.searchURL,
            aliases: engine.aliases,
            isAIChat: engine.isAIChat,
            acceptsQueryInAddress: engine.acceptsQueryInAddress
        ) { [weak settings] withIcon in
            // Unless changed again meanwhile.
            guard settings?.customSearchEngines.first(where: { $0.id == engine.id }) == engine else { return }
            settings?.updateCustomSearchEngine(withIcon)
        }
    }

    private func remove() {
        guard let existing = existingCustom else { return }
        settings.removeCustomSearchEngine(withId: existing.id)
        rename(existing.name, to: nil)
        dismiss()
    }

    /// An engine now of the other kind is no longer a choice of its old
    /// kind: those go back to the global choice.
    private func dropChoices(of name: String, asAI: Bool) {
        if asAI {
            if service.preferences.globalAI == name { service.preferences.globalAI = nil }
        } else if settings.globalDefaultSearchEngine == name {
            settings.globalDefaultSearchEngine = nil
        }
        for space in spaces {
            if asAI, settings.defaultAIEngineId(for: space.id) == name {
                settings.setDefaultAIEngineId(nil, for: space.id)
            } else if !asAI, settings.defaultSearchEngineId(for: space.id) == name {
                settings.setDefaultSearchEngineId(nil, for: space.id)
            }
        }
    }

    /// Choices naming the engine follow its new name; removed (nil), they
    /// go back to the global choice.
    private func rename(_ old: String, to new: String?) {
        if settings.globalDefaultSearchEngine == old { settings.globalDefaultSearchEngine = new }
        for space in spaces {
            if settings.defaultSearchEngineId(for: space.id) == old {
                settings.setDefaultSearchEngineId(new, for: space.id)
            }
            if settings.defaultAIEngineId(for: space.id) == old {
                settings.setDefaultAIEngineId(new, for: space.id)
            }
        }
        service.preferences.rename(old, to: new)
    }
}
