import SwiftUI

/// The assistant's colors, outside the skies.
enum OnboardingInk {
    /// Text on the skies.
    static let light = Color(hex: "#FFF6EE")
    /// Text on the peach buttons and badges.
    static let dark = Color(hex: "#2A1240")
    static let muted = Color(hex: "#D4CAF2")
    static let eyebrow = Color(hex: "#FFC9A6")
    static let peach = Color(hex: "#FFB38A")

    static let primaryGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#FFC49E"), location: 0),
            .init(color: Color(hex: "#FF8F86"), location: 0.55),
            .init(color: Color(hex: "#F06BA8"), location: 1)
        ],
        startPoint: UnitPoint(x: 0, y: 0.3),
        endPoint: UnitPoint(x: 1, y: 0.7)
    )
}

// MARK: - Text

/// The small capitals above a step's title ("Step 2 · Moving in").
struct OnboardingEyebrow: View {
    let text: String
    var color = OnboardingInk.eyebrow

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .tracking(2.4)
            .foregroundStyle(color)
    }
}

/// Shows its content after `delay`, rising a little; at once with Reduce
/// Motion (the screen's own fade is enough) or when `isEnabled` is false.
struct OnboardingFadeUp: ViewModifier {
    var delay: Double = 0
    var distance: CGFloat = 12
    var duration = 0.7
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        let shown = isShown || !isEnabled || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .onAppear {
                guard isEnabled, !isShown, !reduceMotion else { return }
                withAnimation(.easeOut(duration: duration).delay(delay)) { isShown = true }
            }
    }
}

extension View {
    func onboardingFadeUp(delay: Double = 0, distance: CGFloat = 12, isEnabled: Bool = true) -> some View {
        modifier(OnboardingFadeUp(delay: delay, distance: distance, isEnabled: isEnabled))
    }
}

// MARK: - Buttons

/// The main button: peach to pink with dark text.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var isLarge = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isLarge ? 17 : 16, weight: .black))
            .foregroundStyle(OnboardingInk.dark)
            .padding(.horizontal, isLarge ? 30 : 24)
            .frame(height: isLarge ? 52 : 48)
            .background(Capsule().fill(OnboardingInk.primaryGradient))
            .shadow(color: Color(hex: "#F06BA8").opacity(0.4), radius: 15, y: 10)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .contentShape(Capsule())
    }
}

/// A translucent button beside the main one.
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Color(hex: "#F3EEFF"))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Back: text only.
struct OnboardingTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(OnboardingInk.muted)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Progress

/// One dot per step; the current one is a glowing dash.
struct OnboardingProgressDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< count, id: \.self) { dot in
                Capsule()
                    .fill(color(dot))
                    .frame(width: dot == index ? 22 : 8, height: 8)
                    .shadow(color: dot == index ? OnboardingInk.peach.opacity(0.7) : .clear, radius: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }

    private func color(_ dot: Int) -> Color {
        if dot == index { return OnboardingInk.peach }
        return dot < index ? OnboardingInk.peach.opacity(0.6) : Color.white.opacity(0.25)
    }
}

// MARK: - Glow

/// The soft pink light around a planet.
struct OnboardingGlow: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: Color(hex: "#FF8F7A").opacity(0.55), location: 0),
                    .init(color: Color(hex: "#E9579B").opacity(0.2), location: 0.5),
                    .init(color: Color(hex: "#E9579B").opacity(0), location: 0.72)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size / 2
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
