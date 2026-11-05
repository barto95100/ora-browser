import SwiftUI

/// The translation panel, over the page (like Zen's): the page's language,
/// the language to translate into, where the translation stands or why it
/// failed, the original a click away, and "always" / "never" choices.
struct PageTranslationPanel: View {
    let tab: Tab
    let runtime: TabRuntime

    @State private var languages: [Locale.Language] = []
    @State private var target = PageTranslationSettings.standard.targetLanguage.minimalIdentifier
    @State private var alwaysTranslates = false
    @State private var neverOnThisSite = false

    private var settings: PageTranslationSettings {
        .standard
    }

    private var state: PageTranslationState {
        runtime.translation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let source = runtime.pageLanguage {
                languagesForm(source: source)
                status
                actions
                if !tab.isPrivate {
                    Divider()
                    choices(source: source)
                }
            } else {
                Text("Ombre couldn't tell which language this page is in.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 290)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .onExitCommand { close() }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "translate")
            Text("Translate this page").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private func languagesForm(source: Locale.Language) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("From").foregroundStyle(.secondary)
                Text(PageLanguage.name(of: source))
            }
            GridRow {
                Text("To").foregroundStyle(.secondary)
                Picker("To", selection: $target) {
                    ForEach(targetChoices(excluding: source), id: \.minimalIdentifier) { language in
                        Text(Self.displayName(of: language)).tag(language.minimalIdentifier)
                    }
                }
                .labelsHidden()
                .disabled(state.isBusy)
                .onChange(of: target) { _, newValue in
                    settings.setTargetLanguage(Locale.Language(identifier: newValue))
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case let .preparing(pair):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for macOS to download \(PageLanguage.name(of: pair.source))…")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
        case let .translating(_, done, total):
            VStack(alignment: .leading, spacing: 4) {
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                    Text("Translating… \(done) of \(total) pieces of text").foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                    Text("Starting…").foregroundStyle(.secondary)
                }
            }
        case let .translated(pair):
            Text("Translated into \(PageLanguage.name(of: pair.target)) on this Mac.")
                .foregroundStyle(.secondary)
        case let .failed(_, message, _):
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        case .original:
            EmptyView()
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            if state != .original {
                Button(state.isBusy ? "Stop" : "Show Original") {
                    tab.showOriginalPage()
                }
            }
            if !state.isBusy {
                Button("Translate") {
                    tab.translatePage(to: Locale.Language(identifier: target))
                    // The button shows the progress; the panel comes back on failure.
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isShownIn(target))
            }
        }
    }

    private func choices(source: Locale.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Always translate \(PageLanguage.name(of: source))", isOn: $alwaysTranslates)
                .onChange(of: alwaysTranslates) { _, always in
                    settings.setAlwaysTranslates(source, always)
                }
            if let site = PageTranslationSettings.site(tab.url.host) {
                Toggle("Never translate \(site)", isOn: $neverOnThisSite)
                    .onChange(of: neverOnThisSite) { _, never in
                        settings.setNeverTranslates(host: site, never)
                    }
            }
        }
        .toggleStyle(.checkbox)
    }

    /// Already shown in that language: nothing to do.
    private func isShownIn(_ identifier: String) -> Bool {
        guard case let .translated(pair) = state else { return false }
        return pair.target.minimalIdentifier == identifier
    }

    /// The languages to translate into, by name; the chosen one always among them.
    private func targetChoices(excluding source: Locale.Language) -> [Locale.Language] {
        var choices = languages.filter { $0.languageCode != source.languageCode }
        if !choices.contains(where: { $0.minimalIdentifier == target }) {
            choices.insert(Locale.Language(identifier: target), at: 0)
        }
        return choices.sorted { Self.displayName(of: $0) < Self.displayName(of: $1) }
    }

    static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func load() async {
        if let source = runtime.pageLanguage { alwaysTranslates = settings.alwaysTranslates(source) }
        neverOnThisSite = settings.neverTranslates(host: tab.url.host)
        languages = await PageLanguage.supportedLanguages()
    }

    private func close() {
        runtime.showsTranslationPanel = false
    }
}
