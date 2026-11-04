import SwiftUI

/// What the welcome logo shows, layer after layer.
enum LogoStage: Int, Comparable {
    case hidden
    case globe
    case veil
    case wave

    static func < (lhs: LogoStage, rhs: LogoStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Each stage and the wait before it. With Reduce Motion, the finished
    /// logo at once.
    static func timeline(reduceMotion: Bool) -> [(stage: LogoStage, delay: Duration)] {
        if reduceMotion {
            return [(.wave, .zero)]
        }
        return [(.globe, .milliseconds(150)), (.veil, .milliseconds(450)), (.wave, .milliseconds(900))]
    }

    /// How long until the logo is complete: the welcome text waits for it.
    static func duration(reduceMotion: Bool) -> Duration {
        timeline(reduceMotion: reduceMotion).reduce(.zero) { $0 + $1.delay }
    }
}

/// Ombre's icon drawn from the layers of `Ombre.icon`: the globe appears,
/// the veil comes down over it, then the wave shows.
struct OmbreAnimatedLogo: View {
    var size: CGFloat = 128

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var stage = LogoStage.hidden

    var body: some View {
        ZStack {
            Image("onboarding-globe")
                .resizable()
                .opacity(stage >= .globe ? globeOpacity : 0)
                .scaleEffect(stage >= .globe ? 1 : 0.9)
            Image("onboarding-voile")
                .resizable()
                .opacity(stage >= .veil ? 1 : 0)
                .offset(y: stage >= .veil ? 0 : -size * 0.4)
                // Within the globe: the veil comes down over it, not over the
                // tile (the globe's diameter is 640 of the icon's 1024).
                .mask(Circle().frame(width: size * 0.625, height: size * 0.625))
            Image("onboarding-vague")
                .resizable()
                .opacity(stage >= .wave ? 1 : 0)
        }
        .frame(width: size, height: size)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.03)
        .accessibilityHidden(true)
        .task {
            // Once: never backwards if the task runs again.
            guard stage == .hidden else { return }
            for step in LogoStage.timeline(reduceMotion: reduceMotion) {
                do {
                    try await Task.sleep(for: step.delay)
                } catch {
                    return
                }
                withAnimation(reduceMotion ? nil : animation(for: step.stage)) {
                    stage = step.stage
                }
            }
        }
    }

    /// The icon's background: Icon Composer's light and dark gradients.
    private var background: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.165, green: 0.122, blue: 0.4), Color(.displayP3, red: 0.047, green: 0.035, blue: 0.149)]
            : [.white, Color(.displayP3, red: 0.921, green: 0.903, blue: 0.963)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Like the icon: the globe is a little see-through in light mode.
    private var globeOpacity: Double {
        colorScheme == .dark ? 1 : 0.8
    }

    private func animation(for stage: LogoStage) -> Animation {
        switch stage {
        case .hidden, .globe: .easeOut(duration: 0.5)
        case .veil: .spring(duration: 1.0, bounce: 0)
        case .wave: .easeInOut(duration: 0.6)
        }
    }
}
