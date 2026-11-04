import SwiftData
import SwiftUI

/// The first-launch assistant's window: one screen per step, the progress
/// dots and the buttons at the bottom. Finishing (or closing the window)
/// hands the plan to the browser window it opens.
struct OnboardingView: View {
    @StateObject private var model: OnboardingModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(modelContext: ModelContext, isDefaultBrowser: Bool) {
        _model = StateObject(wrappedValue: OnboardingModel(
            modelContext: modelContext,
            isDefaultBrowser: isDefaultBrowser
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepView(model.flow.current)
                    .id(model.flow.current)
                    // Opacity only: the screens hold AppKit controls,
                    // which don't follow moves.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: reduceMotion ? 0.15 : 0.3).delay(0.1)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(width: 800, height: 600)
        .background(VisualEffectBackground())
        // The footer's buttons change in place with Reduce Motion; the screens
        // keep their own short fade (see the transition).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.flow.current)
        .preferredColorScheme(model.choices.appearance.colorScheme)
        .onDisappear {
            // Closed with the window's button: the defaults, done all the same.
            finish(asConfirmed: false)
        }
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: OnboardingWelcomeStep()
        case .importZen: OnboardingImportStep(model: model)
        case .spaces: OnboardingSpacesStep(model: model)
        case .protection: OnboardingProtectionStep(choices: $model.choices)
        case .defaultBrowser: OnboardingDefaultBrowserStep()
        case .ready: OnboardingReadyStep()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.flow.canGoBack {
                OmbreButton(label: "Back", variant: .ghost) { model.back() }
            }
            Spacer()
            progressDots
            Spacer()
            buttons
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.flow.steps.enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(index == model.flow.index ? theme.foreground : theme.foreground.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(model.flow.index + 1) of \(model.flow.steps.count)")
    }

    @ViewBuilder
    private var buttons: some View {
        switch model.flow.current {
        case .welcome:
            OmbreButton(label: "Skip Setup", variant: .ghost) { finish(asConfirmed: false) }
            OmbreButton(label: "Get Started", keyboardShortcut: "return") { model.goOn() }
        case .importZen:
            OmbreButton(label: "Skip", variant: .secondary) { model.skip() }
            OmbreButton(label: importLabel, keyboardShortcut: "return") { model.goOn() }
        case .spaces, .protection:
            OmbreButton(label: "Skip", variant: .secondary) { model.skip() }
            OmbreButton(label: "Continue", keyboardShortcut: "return") { model.goOn() }
        case .defaultBrowser:
            OmbreButton(label: "Not Now", variant: .secondary) { model.skip() }
            OmbreButton(label: "Set as Default", keyboardShortcut: "return") {
                DefaultBrowserManager.shared.requestSetAsDefault()
                model.goOn()
            }
        case .ready:
            OmbreButton(label: "Start Browsing", keyboardShortcut: "return") { finish(asConfirmed: true) }
        }
    }

    private var importLabel: String {
        switch model.choices.importedSpaces.count {
        case 0: "Continue"
        case 1: "Import 1 Space"
        case let count: "Import \(count) Spaces"
        }
    }

    // MARK: - Finish

    private func finish(asConfirmed: Bool) {
        guard let result = model.finish(asConfirmed: asConfirmed) else { return }
        OnboardingStatus.markDone()
        OnboardingHandoff.hand(result)
        openWindow(id: "normal")
        dismissWindow(id: "onboarding")
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The window's translucent background.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
