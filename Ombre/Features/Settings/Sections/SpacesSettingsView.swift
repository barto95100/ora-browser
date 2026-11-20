import SwiftData
import SwiftUI

// swiftlint:disable type_body_length large_tuple
struct SpacesSettingsView: View {
    private enum ClearDataAction: Hashable {
        case cache(UUID)
        case cookies(UUID)
        case history(UUID)
    }

    @Query(sort: TabContainer.displayOrder) var containers: [TabContainer]

    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var searchService = SearchEngineService()
    @State private var selectedContainerId: UUID?
    @State private var completedClearActions: Set<ClearDataAction> = []
    @State private var newCustomFilterListURL = ""
    @State private var spacePendingDeletion: TabContainer?
    /// New Space… was clicked: the space that appears next is selected.
    @State private var awaitsNewSpace = false
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var toastManager: ToastManager

    private var selectedContainer: TabContainer? {
        containers.first { $0.id == selectedContainerId } ?? containers.first
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left list
            VStack(spacing: 0) {
                List(selection: $selectedContainerId) {
                    ForEach(containers) { container in
                        HStack {
                            Text(container.emoji)
                            Text(container.name)
                        }
                        .tag(container.id)
                        .contextMenu {
                            Button("Delete Space…", role: .destructive) { spacePendingDeletion = container }
                                .disabled(containers.count <= 1)
                        }
                    }
                }
                Divider()
                HStack {
                    Menu {
                        Button("New Space…") {
                            awaitsNewSpace = true
                            BrowserWindows.newSpace()
                        }
                        Divider()
                        Button("Import from Safari…") { BrowserWindows.showImport(from: .safari) }
                        Button("Import from Arc…") { BrowserWindows.showImport(from: .arc) }
                        Button("Import from Zen…") { BrowserWindows.showImport(from: .zen) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(String(localized: "New Space or Import"))
                    .accessibilityLabel(String(localized: "New Space or Import"))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 200, idealWidth: 200, maxWidth: 220)
            // A space just made with New Space… is shown at once.
            .onChange(of: containers.map(\.id)) { old, new in
                guard awaitsNewSpace, let added = new.first(where: { !old.contains($0) }) else { return }
                awaitsNewSpace = false
                selectedContainerId = added
            }

            Divider()

            // Right details
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let container = selectedContainer {
                        SettingsCard(
                            header: String(localized: "Search and AI"),
                            description: String(
                                localized: "This space’s address bar searches with this engine and asks this AI, with the space’s own cookies."
                            )
                        ) {
                            SettingsRow(title: String(localized: "Search Engine")) {
                                enginePicker(for: container, isAI: false)
                            }
                            Divider()
                            SettingsRow(title: String(localized: "settings.search.ai", defaultValue: "AI")) {
                                enginePicker(for: container, isAI: true)
                            }
                        }

                        SettingsCard(header: String(localized: "Tabs")) {
                            SettingsRow(
                                title: String(localized: "Auto Clear Tabs"),
                                detail: String(localized: "The shorter of this delay and the general one applies.")
                            ) {
                                ClosingDelayPicker(
                                    seconds: Binding(
                                        get: { settings.spaceClosingDelay(for: container.id) },
                                        set: { settings.setSpaceClosingDelay($0, for: container.id) }
                                    ),
                                    generalTitle: String(
                                        localized: "Like General (\(TabClosingDelay.title(settings.tabRemovalTimeout)))"
                                    )
                                )
                            }
                            Divider()
                            SettingsRow(
                                title: String(localized: "Group tabs automatically"),
                                detail: String(
                                    localized: "By site, from three tabs of a site. Tabs › Tidy Tabs Now groups them at any time."
                                )
                            ) {
                                Toggle("", isOn: Binding(
                                    get: { settings.autoGroupsTabs(for: container.id) },
                                    set: { settings.setAutoGroupsTabs($0, for: container.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                        }

                        privacySettingsCard(for: container)
                        SitePermissionsSettingsCard(container: container)
                        adBlockingSettingsCard(for: container)

                        SettingsCard(header: String(localized: "Clear Data")) {
                            VStack(spacing: 8) {
                                Button(
                                    clearDataButtonTitle(
                                        for: .cache(container.id),
                                        defaultTitle: String(localized: "Clear Cache"),
                                        completedTitle: String(localized: "Cache Cleared")
                                    )
                                ) {
                                    PrivacyService.clearCache(container) {
                                        DispatchQueue.main.async {
                                            completedClearActions.insert(.cache(container.id))
                                            toastManager.show(
                                                String(localized: "Cache cleared"),
                                                icon: .system("trash")
                                            )
                                        }
                                    }
                                }
                                .disabled(completedClearActions.contains(.cache(container.id)))
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(
                                    clearDataButtonTitle(
                                        for: .cookies(container.id),
                                        defaultTitle: String(localized: "Clear Cookies"),
                                        completedTitle: String(localized: "Cookies Cleared")
                                    )
                                ) {
                                    PrivacyService.clearCookies(container) {
                                        DispatchQueue.main.async {
                                            completedClearActions.insert(.cookies(container.id))
                                            toastManager.show(
                                                String(localized: "Cookies cleared"),
                                                icon: .system("trash")
                                            )
                                        }
                                    }
                                }
                                .disabled(completedClearActions.contains(.cookies(container.id)))
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(
                                    clearDataButtonTitle(
                                        for: .history(container.id),
                                        defaultTitle: String(localized: "Clear History"),
                                        completedTitle: String(localized: "History Cleared")
                                    )
                                ) {
                                    if clearHistory(for: container) {
                                        completedClearActions.insert(.history(container.id))
                                        toastManager.show(String(localized: "History cleared"), icon: .system("trash"))
                                    }
                                }
                                .disabled(completedClearActions.contains(.history(container.id)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }

                        deleteSpaceCard(for: container)
                    } else {
                        Text("No spaces found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .confirmationDialog(
            "Delete “\(spacePendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { spacePendingDeletion != nil },
                set: { if !$0 { spacePendingDeletion = nil } }
            ),
            presenting: spacePendingDeletion
        ) { container in
            Button("Delete", role: .destructive) { delete(container) }
        } message: { _ in
            Text("All tabs in this space will be permanently removed.")
        }
        .onAppear {
            if selectedContainerId == nil { selectedContainerId = containers.first?.id }
            Task {
                for container in containers {
                    await AdBlockService.shared.registerSpace(containerId: container.id)
                }
            }
        }
    }

    /// The space's engine or AI: « Use Global Choice » (the default) or one
    /// engine; a chosen engine shows (see `SearchEngineService.choose`).
    private func enginePicker(for container: TabContainer, isAI: Bool) -> some View {
        let rules = searchService.rules
        let global = isAI ? rules.defaultAIName : rules.defaultSearchName
        return Picker(
            "",
            selection: Binding(
                get: {
                    isAI ? settings.defaultAIEngineId(for: container.id)
                        : settings.defaultSearchEngineId(for: container.id)
                },
                set: { searchService.choose($0, isAI: isAI, for: container.id) }
            )
        ) {
            Text("Use Global Choice (\(global))").tag(nil as String?)
            Divider()
            ForEach(rules.engines.filter { $0.isAIChat == isAI }, id: \.name) { engine in
                Text(engine.name).tag(Optional(engine.name))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private func deleteSpaceCard(for container: TabContainer) -> some View {
        SettingsCard(header: String(localized: "Delete Space")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    containers.count <= 1
                        ? "The last space can't be deleted."
                        : "Removes the space with its tabs, folders and website data."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Delete Space…", role: .destructive) { spacePendingDeletion = container }
                    .disabled(containers.count <= 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The browser window deletes it, like from the sidebar (see `BrowserWindows`).
    private func delete(_ container: TabContainer) {
        if selectedContainerId == container.id {
            selectedContainerId = containers.first { $0.id != container.id }?.id
        }
        BrowserWindows.deleteSpace(container.id)
        spacePendingDeletion = nil
    }

    private func clearHistory(for container: TabContainer) -> Bool {
        HistoryManager(modelContainer: modelContext.container, modelContext: modelContext)
            .clearContainerHistory(container)
    }

    private func clearDataButtonTitle(
        for action: ClearDataAction,
        defaultTitle: String,
        completedTitle: String
    ) -> String {
        completedClearActions.contains(action) ? completedTitle : defaultTitle
    }

    private func privacySettingsCard(for container: TabContainer) -> some View {
        SettingsCard(header: String(localized: "Privacy")) {
            Text(
                "These protections apply only to \(container.name). Open tabs in this space are refreshed automatically."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Toggle(
                "Block third-party trackers",
                isOn: privacyBinding(for: container, keyPath: \.blockThirdPartyTrackers)
            )
            Toggle(
                "Block fingerprinting",
                isOn: privacyBinding(for: container, keyPath: \.blockFingerprinting)
            )

            Text(
                "Reduces browser and device fingerprint surface for this space. This does not block cookies or other storage by itself."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Picker(
                "Cookies",
                selection: privacyBinding(for: container, keyPath: \.cookiesPolicy)
            ) {
                ForEach(CookiesPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    @ViewBuilder
    private func adBlockingSettingsCard(for container: TabContainer) -> some View {
        let privacySettings = settings.privacySettings(for: container.id)
        let enabledRecords = enabledAdBlockRecords(for: container)
        let builtinRecords = settings.adBlockFilterLists.filter(\.isBuiltin)
        let customRecords = settings.adBlockFilterLists.filter { $0.sourceKind == .custom }
        let summary = adBlockSummary(for: container)

        SettingsCard(
            header: String(localized: "Ad Blocking"),
            description: String(
                localized: "Powered by embedded AdGuard filter lists compiled for WebKit in this space."
            )
        ) {
            Toggle("Enable Ad Blocking", isOn: adBlockEnabledBinding(for: container))

            Divider()

            Picker("Update Policy", selection: adBlockUpdateModeBinding(for: container)) {
                ForEach(AdBlockUpdateMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 12) {
                Button("Refresh Now") {
                    Task {
                        let changed = await AdBlockService.shared.refreshSpace(
                            containerId: container.id,
                            reason: .manual
                        )
                        _ = await MainActor.run {
                            toastManager.show(
                                changed ? String(localized: "Filter lists updated for \(container.name)") :
                                    String(localized: "Filter lists are already current"),
                                type: .info,
                                icon: .system("arrow.clockwise.circle")
                            )
                        }
                    }
                }
                .disabled(!privacySettings.adBlock.enabled || enabledRecords.isEmpty || summary.isUpdating)

                if summary.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.subheadline.weight(.semibold))
                Text(summary.statusText)
                    .foregroundStyle(summary.hasFailures ? .red : .secondary)
                if let lastUpdatedText = summary.lastUpdatedText {
                    Text("Last updated \(lastUpdatedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let coverageText = summary.coverageText {
                    Text(coverageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-In Lists")
                    .font(.subheadline.weight(.semibold))

                ForEach(builtinRecords) { record in
                    filterListRow(for: container, record: record, showRemoveButton: false)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Lists")
                    .font(.subheadline.weight(.semibold))

                HStack(alignment: .center, spacing: 10) {
                    TextField("https://example.com/filter.txt", text: $newCustomFilterListURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addCustomFilterList(for: container)
                    }
                    .disabled(newCustomFilterListURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if customRecords.isEmpty {
                    Text("Add a remote AdGuard-style list URL to make it available in this space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRecords) { record in
                        filterListRow(for: container, record: record, showRemoveButton: true)
                    }
                }
            }
        }
    }

    private func filterListRow(
        for container: TabContainer,
        record: FilterListRecord,
        showRemoveButton: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(isOn: adBlockFilterBinding(for: container, record: record)) {
                    VStack(alignment: .leading, spacing: 4) {
                        if record.sourceKind == .custom {
                            TextField(
                                "Custom list name",
                                text: customFilterNameBinding(for: record)
                            )
                            .textFieldStyle(.roundedBorder)
                        } else {
                            Text(record.name)
                                .font(.body.weight(.medium))
                        }
                        Text(FilterListCatalogService.shared.summary(of: record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(filterListStatusText(for: record))
                            .font(.caption)
                            .foregroundStyle(record.status == .failed ? .red : .secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if showRemoveButton {
                    Button("Remove", role: .destructive) {
                        Task {
                            await AdBlockService.shared.removeCustomList(id: record.id)
                            _ = await MainActor.run {
                                toastManager.show(
                                    String(localized: "Removed \(record.name)"),
                                    type: .info,
                                    icon: .system("trash")
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func privacyBinding<Value>(
        for container: TabContainer,
        keyPath: WritableKeyPath<SpacePrivacySettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.privacySettings(for: container.id)[keyPath: keyPath]
            },
            set: { newValue in
                var updatedSettings = settings.privacySettings(for: container.id)
                updatedSettings[keyPath: keyPath] = newValue
                settings.setPrivacySettings(updatedSettings, for: container.id)
                settings.notifySpacePrivacySettingsChanged(for: container.id)
            }
        )
    }

    private func adBlockEnabledBinding(for container: TabContainer) -> Binding<Bool> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.enabled
            },
            set: { newValue in
                applyAdBlockSettingsChange(for: container) { updatedSettings in
                    updatedSettings.adBlock.enabled = newValue
                }
            }
        )
    }

    private func adBlockUpdateModeBinding(for container: TabContainer) -> Binding<AdBlockUpdateMode> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.updateMode
            },
            set: { newValue in
                var updatedSettings = settings.privacySettings(for: container.id)
                updatedSettings.adBlock.updateMode = newValue
                settings.setPrivacySettings(updatedSettings, for: container.id)
                Task {
                    await AdBlockService.shared.spaceSettingsDidChange(containerId: container.id)
                }
            }
        )
    }

    private func adBlockFilterBinding(for container: TabContainer, record: FilterListRecord) -> Binding<Bool> {
        Binding(
            get: {
                settings.privacySettings(for: container.id).adBlock.isEnabled(record)
            },
            set: { isEnabled in
                applyAdBlockSettingsChange(for: container) { updatedSettings in
                    updatedSettings.adBlock.setEnabled(isEnabled, for: record)
                }
            }
        )
    }

    private func customFilterNameBinding(for record: FilterListRecord) -> Binding<String> {
        Binding(
            get: {
                settings.adBlockFilterList(id: record.id)?.name ?? record.name
            },
            set: { newValue in
                guard var updatedRecord = settings.adBlockFilterList(id: record.id) else { return }
                updatedRecord.name = newValue
                settings.upsertAdBlockFilterList(updatedRecord)
            }
        )
    }

    private func addCustomFilterList(for container: TabContainer) {
        let submittedURL = newCustomFilterListURL
        Task {
            do {
                let record = try await AdBlockService.shared.addCustomList(sourceURL: submittedURL)
                await AdBlockService.shared.spaceSettingsDidChange(containerId: container.id)
                _ = await MainActor.run {
                    newCustomFilterListURL = ""
                    toastManager.show(String(localized: "Added \(record.name)"), icon: .system("checkmark.circle"))
                }
            } catch {
                _ = await MainActor.run {
                    toastManager.show(error.localizedDescription, type: .error)
                }
            }
        }
    }

    private func applyAdBlockSettingsChange(
        for container: TabContainer,
        mutate: (inout SpacePrivacySettings) -> Void
    ) {
        var updatedSettings = settings.privacySettings(for: container.id)
        mutate(&updatedSettings)
        settings.setPrivacySettings(updatedSettings, for: container.id)
        Task {
            await AdBlockService.shared.refreshSpace(containerId: container.id, reason: .settingsChanged)
        }
    }

    private func enabledAdBlockRecords(for container: TabContainer) -> [FilterListRecord] {
        let enabledListIDs = Set(settings.privacySettings(for: container.id).adBlock.enabledListIDs)
        return settings.adBlockFilterLists.filter { enabledListIDs.contains($0.id) }
    }

    private func filterListStatusText(for record: FilterListRecord) -> String {
        switch record.status {
        case .idle:
            return String(localized: "Not downloaded yet")
        case .updating:
            return String(localized: "Updating list and compiling WebKit rules")
        case .ready:
            return if let coverage = record.coverage {
                String(
                    localized: "Rules: \(coverage.convertedRuleCount) converted, \(coverage.skippedRuleCount) skipped"
                )
            } else {
                String(localized: "Compiled and ready")
            }
        case .failed:
            return record.lastErrorMessage ?? String(localized: "The list could not be refreshed")
        }
    }

    private func adBlockSummary(for container: TabContainer) -> (
        statusText: String,
        lastUpdatedText: String?,
        coverageText: String?,
        isUpdating: Bool,
        hasFailures: Bool
    ) {
        let privacySettings = settings.privacySettings(for: container.id)
        guard privacySettings.adBlock.enabled else {
            return (String(localized: "Ad blocking is off for this space."), nil, nil, false, false)
        }

        let enabledRecords = enabledAdBlockRecords(for: container)
        guard !enabledRecords.isEmpty else {
            return (
                String(localized: "Select at least one filter list to block ads in this space."),
                nil,
                nil,
                false,
                false
            )
        }

        let isUpdating = enabledRecords.contains { $0.status == .updating }
        let failedRecords = enabledRecords.filter { $0.status == .failed }
        let lastUpdated = enabledRecords.compactMap(\.lastSuccessfulRefreshAt).max()
        let totalConverted = enabledRecords.compactMap(\.coverage).reduce(0) { $0 + $1.convertedRuleCount }
        let totalSkipped = enabledRecords.compactMap(\.coverage).reduce(0) { $0 + $1.skippedRuleCount }

        let statusText = if isUpdating {
            String(localized: "Updating filter lists and recompiling WebKit rule sets.")
        } else if let failedRecord = failedRecords.first {
            String(localized: "\(failedRecord.name) needs attention.")
        } else {
            String(localized: "Ready in \(enabledRecords.count) enabled lists.")
        }

        let lastUpdatedText = lastUpdated?.formatted(date: .abbreviated, time: .shortened)
        let coverageText = totalConverted == 0 && totalSkipped == 0
            ? nil
            : String(localized: "Rules: \(totalConverted) converted, \(totalSkipped) skipped")

        return (statusText, lastUpdatedText, coverageText, isUpdating, !failedRecords.isEmpty)
    }
}

// swiftlint:enable type_body_length large_tuple
