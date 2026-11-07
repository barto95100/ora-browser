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
/// Turns while translating (with the share done), never without end.
struct PageTranslationButton: View {
    let tab: Tab
    let runtime: TabRuntime
    let foregroundColor: Color
    /// Drawn over a dark color: the system spinner is drawn light.
    var isOverDark = false

    private var help: String {
        switch runtime.translation {
        case .original: "Translate this page"
        case .preparing: "Waiting for the language download…"
        case let .translating(_, done, total): total > 0 ? "Translating… \(done) of \(total)" : "Translating…"
        case .translated: "Translated: show the original or change the language"
        case .failed: "The translation failed"
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
        case let .translating(_, done, total) where total > 0:
            // Drawn here, in the bar's readable color: AppKit's own ring
            // keeps the system's colors, unseen over a bright header.
            ZStack {
                Circle().stroke(foregroundColor.opacity(0.35), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                    .stroke(foregroundColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
        case .preparing, .translating:
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
