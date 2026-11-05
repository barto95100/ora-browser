import SwiftUI
import Translation

/// Runs a page's translation with Apple's Translation, on the Mac: the
/// session (and the offer to download a language) comes with the view.
struct PageTranslationHost: View {
    let tab: Tab
    let runtime: TabRuntime

    private var configuration: TranslationSession.Configuration? {
        guard case let .translating(source) = runtime.translation else { return nil }
        return TranslationSession.Configuration(source: source, target: PageLanguage.userLanguage)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .translationTask(configuration) { session in
                await tab.translatePage(with: session)
            }
    }
}

/// The address bar's translate button: shown when the page is in another
/// language than the Mac's; shows the original again once translated.
struct PageTranslationButton: View {
    let tab: Tab
    let runtime: TabRuntime
    let foregroundColor: Color

    private var isTranslated: Bool {
        if case .translated = runtime.translation { return true }
        return false
    }

    private var help: String {
        let target = Locale.current
            .localizedString(forLanguageCode: PageLanguage.userLanguage.languageCode?.identifier ?? "")
            ?? "your language"
        switch runtime.translation {
        case .translated: return "Show Original"
        case .translating: return "Translating…"
        default: return "Translate to \(target)"
        }
    }

    var body: some View {
        if runtime.translation != .unavailable {
            Button {
                tab.toggleTranslation()
            } label: {
                Group {
                    if case .translating = runtime.translation {
                        ProgressView().scaleEffect(0.45)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 11, weight: .medium))
                            .symbolVariant(isTranslated ? .fill : .none)
                    }
                }
                .foregroundColor(foregroundColor)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
        }
    }
}
