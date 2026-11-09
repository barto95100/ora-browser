import SwiftUI
import Translation

/// Gives a translation the session of the page's view, when it needs one:
/// macOS shows its prompt to download a language over this view, and before
/// macOS 26 a session only comes from a view.
struct PageTranslationHost: View {
    let tab: Tab
    let runtime: TabRuntime

    private var configuration: TranslationSession.Configuration? {
        runtime.translationRequest?.configuration
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .translationTask(configuration) { session in
                guard let request = runtime.translationRequest else { return }
                await tab.runTranslation(with: session, for: request)
            }
    }
}

/// The address bar's translate button: shown when the page is in another
/// language than the Mac's, or translated; opens the translation panel.
/// While translating, a ring around the translate sign fills with the
/// share done; a spinner only while macOS downloads a language.
struct PageTranslationButton: View {
    let tab: Tab
    let runtime: TabRuntime
    let foregroundColor: Color
    /// Drawn over a dark color: the system spinner is drawn light.
    var isOverDark = false

    private var help: String {
        switch runtime.translation {
        case .original: String(localized: "Translate this page")
        case .preparing: String(localized: "Waiting for the language download…")
        case .translating: runtime.translation.percentDone
            .map { String(localized: "Translating… \($0)%") } ?? String(localized: "Translating…")
        case .translated: String(localized: "Translated: show the original or change the language")
        case .failed: String(localized: "The translation failed")
        }
    }

    var body: some View {
        if tab.showsTranslationButton {
            Button {
                runtime.showsTranslationPanel.toggle()
            } label: {
                icon
                    .foregroundColor(foregroundColor)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch runtime.translation {
        case .translating:
            // The translate sign inside a ring filling as the page is
            // translated: never mistaken for a download. Drawn here, in the
            // bar's readable color (AppKit's ring keeps the system's colors).
            TranslationProgressRing(progress: runtime.translation.progress ?? 0, color: foregroundColor)
        case .preparing:
            // Only a language macOS downloads first (its prompt is shown).
            ProgressView()
                .scaleEffect(0.45)
                .environment(\.colorScheme, isOverDark ? .dark : .light)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
        default:
            Image(systemName: "translate")
                .font(.system(size: 11, weight: .medium))
                .symbolVariant(runtime.translation.showsTranslation ? .fill : .none)
        }
    }
}

/// The translate sign inside a ring showing the share translated.
struct TranslationProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
            Image(systemName: "translate")
                .font(.system(size: 7, weight: .semibold))
        }
        .frame(width: 15, height: 15)
    }
}
