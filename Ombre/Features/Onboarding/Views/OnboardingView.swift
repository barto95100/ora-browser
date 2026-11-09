import SwiftData
import SwiftUI

/// The first-launch assistant's window: one screen per step, the progress
/// dots and the buttons at the bottom. Finishing (or closing the window)
/// hands the plan to the browser window it opens.
struct OnboardingView: View {
    @StateObject private var model: OnboardingModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWindowVisible = true
    /// The welcome screen's entrance plays once, not again after Back.
    @State private var playedWelcome = false
    @State private var showsWelcomeFooter = false
    /// The hidden title bar's height: the screens are drawn under it, so
    /// that the whole window is 800 × 600 as designed.
    @State private var titleBarHeight: CGFloat = 32

    init(modelContext: ModelContext, isDefaultBrowser: Bool) {
        _model = StateObject(wrappedValue: OnboardingModel(
            modelContext: modelContext,
            isDefaultBrowser: isDefaultBrowser
        ))
    }

    private var step: OnboardingStep {
        model.flow.current
    }

    var body: some View {
        Color.clear
            .frame(width: 800, height: 600 - titleBarHeight)
            .overlay(alignment: .bottom) { window }
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) { titleBarHeight = $0 }
            }
            .fontDesign(.rounded)
            // The skies have fixed colors: text fields, menus and scroll
            // bars follow them, not the system appearance.
            .environment(\.colorScheme, .dark)
            .background(WindowVisibilityReader(isVisible: $isWindowVisible))
            .environment(\.onboardingAnimationsPaused, !isWindowVisible)
            .task {
                // The welcome buttons come with the end of its entrance.
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(1.9))
                }
                withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.7)) { showsWelcomeFooter = true }
            }
            .onDisappear {
                // Closed with the window's button: the defaults, done all the same.
                finish(asConfirmed: false)
            }
    }

    /// The whole window, title bar included.
    private var window: some View {
        ZStack {
            // The skies fade into each other, the stars come out.
            Group {
                OnboardingSkyBackground(step: step)
                OnboardingStarField(shown: Double(OnboardingNightfall.starCount(for: step)))
            }
            .animation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9), value: step)
            ZStack {
                stepView(step)
                    .id(step)
                    // Opacity only: the screens hold AppKit controls,
                    // which don't follow moves.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: reduceMotion ? 0.2 : 0.45).delay(0.15)),
                        removal: .opacity.animation(.easeIn(duration: 0.2))
                    ))
            }
            .frame(width: 800, height: 600)
            VStack {
                Spacer()
                footer
                    .padding(.horizontal, 32)
                    .padding(.bottom, 34)
                    .opacity(showsFooter ? 1 : 0)
                    .allowsHitTesting(showsFooter)
                    .accessibilityHidden(!showsFooter)
            }
        }
        .frame(width: 800, height: 600)
        .clipped()
        // With Reduce Motion, the footer changes in place.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        .onChange(of: step) { previous, _ in
            if previous == .welcome { playedWelcome = true }
        }
    }

    /// Hidden until the welcome screen's entrance ends.
    private var showsFooter: Bool {
        step != .welcome || showsWelcomeFooter
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep(playsEntrance: !playedWelcome)
        case .importZen: OnboardingImportStep(model: model)
        case .spaces: OnboardingSpacesStep(model: model)
        case .protection: OnboardingProtectionStep(choices: $model.choices, stepNumber: model.flow.index + 1)
        case .defaultBrowser: OnboardingDefaultBrowserStep()
        case .ready: OnboardingReadyStep()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            OnboardingProgressDots(
                count: model.flow.steps.count,
                index: model.flow.index
            )
            HStack(spacing: 10) {
                leadingButton
                Spacer()
                buttons
            }
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var leadingButton: some View {
        if step == .welcome {
            Button("Skip setup") { finish(asConfirmed: false) }
                .buttonStyle(OnboardingSecondaryButtonStyle())
        } else if model.flow.canGoBack {
            Button("Back") { model.back() }
                .buttonStyle(OnboardingTextButtonStyle())
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .welcome:
            primary(String(localized: "Let's go")) { model.goOn() }
        case .importZen:
            secondary(String(localized: "Skip")) { model.skip() }
            primary(importLabel) { model.goOn() }
        case .spaces:
            secondary(String(localized: "Skip")) { model.skip() }
            primary(String(localized: "Looks good")) { model.goOn() }
        case .protection:
            secondary(String(localized: "Skip")) { model.skip() }
            primary(String(localized: "Continue")) { model.goOn() }
        case .defaultBrowser:
            secondary(String(localized: "Not now")) { model.skip() }
            primary(String(localized: "Yes, make it home")) {
                DefaultBrowserManager.shared.requestSetAsDefault()
                model.goOn()
            }
        case .ready:
            primary(String(localized: "Start exploring"), isLarge: true) { finish(asConfirmed: true) }
        }
    }

    private func primary(
        _ label: String,
        isLarge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(label, action: action)
            .buttonStyle(OnboardingPrimaryButtonStyle(isLarge: isLarge))
            .keyboardShortcut(.defaultAction)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(OnboardingSecondaryButtonStyle())
    }

    private var importLabel: String {
        Self.importLabel(count: model.choices.importedSpaces.count)
    }

    static func importLabel(count: Int) -> String {
        count == 0 ? String(localized: "Continue") : String(localized: "Bring \(count) spaces")
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
