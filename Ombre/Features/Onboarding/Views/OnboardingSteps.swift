import SwiftUI

// Each screen fills the 800 × 600 window; the footer (buttons and progress)
// is drawn over it by `OnboardingView`.

// MARK: - 1. Welcome

/// Golden hour, already violet: the planet rises in full sun, then the words come.
struct OnboardingWelcomeStep: View {
    /// False after Back: the screen shows as it ended.
    var playsEntrance = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRisen = false

    var body: some View {
        ZStack {
            OnboardingClock { time in
                ZStack {
                    cloud(width: 170, height: 34, opacity: 0.16, time: time)
                        .position(x: 155, y: 87)
                    cloud(width: 130, height: 26, opacity: 0.12, time: time + 6)
                        .position(x: 625, y: 133)
                    orbit(time: time)
                        .position(x: 400, y: 600)
                    sun(time: time)
                        .position(x: 400, y: 650)
                }
            }
            OmbrePlanet(size: 520, shadow: OnboardingNightfall.shadow(for: .welcome))
                .scaleEffect(risen ? 1 : 0.92)
                .offset(y: risen ? 0 : 170)
                .opacity(risen ? 1 : 0)
                .position(x: 400, y: 578)
            words
                .frame(maxWidth: .infinity)
                .position(x: 400, y: 170)
        }
        .frame(width: 800, height: 600)
        .onAppear {
            guard playsEntrance, !reduceMotion else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.9)) { hasRisen = true }
        }
    }

    private var risen: Bool {
        hasRisen || !playsEntrance || reduceMotion
    }

    private var words: some View {
        VStack(spacing: 14) {
            Text("Bonjour, Hello, Hola".uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(2.9)
                .foregroundStyle(Color(hex: "#FFE0CC"))
                .onboardingFadeUp(delay: 1.2, distance: 14, isEnabled: playsEntrance)
            Text("Welcome to Ombre")
                .font(.system(size: 58, weight: .black))
                .tracking(-1.2)
                .foregroundStyle(LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#FFF6EE"), location: 0.1),
                        .init(color: Color(hex: "#FFD2B6"), location: 0.6),
                        .init(color: Color(hex: "#FFB0CB"), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .onboardingFadeUp(delay: 1.5, distance: 14, isEnabled: playsEntrance)
                .accessibilityAddTraits(.isHeader)
            Text("A calm little planet for the whole web.")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: "#FBE9F2"))
                .onboardingFadeUp(delay: 1.9, distance: 14, isEnabled: playsEntrance)
        }
        .multilineTextAlignment(.center)
    }

    /// Drifts 30 points each way every 14 seconds.
    private func cloud(width: CGFloat, height: CGFloat, opacity: Double, time: TimeInterval) -> some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .offset(x: -30 * cos(time / 14 * .pi))
            .accessibilityHidden(true)
    }

    /// A dashed orbit around the planet, one turn a minute, with a glowing star on it.
    private func orbit(time: TimeInterval) -> some View {
        ZStack(alignment: .top) {
            Circle()
                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            Circle()
                .fill(Color(hex: "#FFFBF5").opacity(0.8))
                .frame(width: 10, height: 10)
                .shadow(color: Color(hex: "#FFFBF5").opacity(0.6), radius: 8)
                .offset(y: -5)
        }
        .frame(width: 1100, height: 1100)
        .rotationEffect(.degrees(time / 60 * 360))
        .accessibilityHidden(true)
    }

    /// The low sun's halo, breathing slowly.
    private func sun(time: TimeInterval) -> some View {
        let breath = 0.5 - 0.5 * cos(time / 5 * 2 * .pi)
        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: Color(hex: "#FFF6E1").opacity(0.5), location: 0),
                    .init(color: Color(hex: "#FFD6AA").opacity(0.28), location: 0.3),
                    .init(color: Color(hex: "#FFB38A").opacity(0), location: 0.62)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 350
            ))
            .frame(width: 700, height: 700)
            .opacity(time == 0 ? 0.9 : 0.75 + 0.25 * breath)
            .scaleEffect(1 + 0.04 * breath)
            .accessibilityHidden(true)
    }
}

// MARK: - 5. Default browser

/// Night: links from the other apps flow to the planet.
struct OnboardingDefaultBrowserStep: View {
    private struct Source {
        let symbol: String
        let color: String
        let center: CGPoint
        /// From the app to the planet: start, two control points, end.
        let curve: [CGPoint]
    }

    private let sources = [
        Source(
            symbol: "envelope", color: "#FFC9A6", center: CGPoint(x: 107, y: 139),
            curve: [CGPoint(x: 120, y: 140), CGPoint(x: 220, y: 120), CGPoint(x: 300, y: 170), CGPoint(x: 360, y: 220)]
        ),
        Source(
            symbol: "bubble.left", color: "#F58AB8", center: CGPoint(x: 83, y: 331),
            curve: [CGPoint(x: 100, y: 330), CGPoint(x: 200, y: 320), CGPoint(x: 280, y: 300), CGPoint(x: 352, y: 262)]
        ),
        Source(
            symbol: "doc.text", color: "#9AD9FF", center: CGPoint(x: 703, y: 149),
            curve: [CGPoint(x: 690, y: 150), CGPoint(x: 590, y: 130), CGPoint(x: 510, y: 170), CGPoint(x: 446, y: 220)]
        ),
        Source(
            symbol: "calendar", color: "#A8F0C8", center: CGPoint(x: 717, y: 331),
            curve: [CGPoint(x: 700, y: 330), CGPoint(x: 600, y: 320), CGPoint(x: 520, y: 300), CGPoint(x: 450, y: 262)]
        )
    ]

    var body: some View {
        ZStack {
            OnboardingClock { time in
                ZStack {
                    ForEach(sources.indices, id: \.self) { index in
                        link(sources[index], time: time)
                    }
                    let pulse = 0.5 - 0.5 * cos(time / 3 * 2 * .pi)
                    OnboardingGlow(size: 200)
                        .scaleEffect(1 + 0.08 * pulse)
                        .opacity(time == 0 ? 0.75 : 0.6 + 0.3 * pulse)
                        .position(x: 400, y: 240)
                }
            }
            ForEach(sources.indices, id: \.self) { index in
                appIcon(sources[index])
            }
            OmbrePlanet(size: 130, shadow: OnboardingNightfall.shadow(for: .defaultBrowser))
                .position(x: 400, y: 240)
            VStack(spacing: 10) {
                Text("Make Ombre your home planet?")
                    .font(.system(size: 36, weight: .black))
                    .tracking(-0.5)
                    .foregroundStyle(OnboardingInk.light)
                    .accessibilityAddTraits(.isHeader)
                Text("Links you open from Mail, Messages and your other apps will land here.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingInk.muted)
            }
            .multilineTextAlignment(.center)
            .onboardingFadeUp(delay: 0.2)
            .position(x: 400, y: 420)
        }
        .frame(width: 800, height: 600)
    }

    /// A dashed link whose dashes run toward the planet.
    private func link(_ source: Source, time: TimeInterval) -> some View {
        Path { path in
            path.move(to: source.curve[0])
            path.addCurve(to: source.curve[3], control1: source.curve[1], control2: source.curve[2])
        }
        .stroke(
            Color(hex: source.color),
            style: StrokeStyle(
                lineWidth: 3,
                lineCap: .round,
                dash: [4, 8],
                dashPhase: -CGFloat(time.truncatingRemainder(dividingBy: 1.6) / 1.6 * 60)
            )
        )
        .accessibilityHidden(true)
    }

    private func appIcon(_ source: Source) -> some View {
        Image(systemName: source.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color(hex: source.color))
            .frame(width: 54, height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .position(source.center)
            .accessibilityHidden(true)
    }
}

// MARK: - 6. Ready

/// The violet night: the finished planet with its ring and moons, confetti.
struct OnboardingReadyStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasPopped = false

    private let shortcuts: [(KeyboardShortcutDefinition, String)] = [
        (KeyboardShortcuts.Tabs.new, "New tab or search"),
        (KeyboardShortcuts.App.toggleSidebar, "Show or hide the sidebar"),
        (KeyboardShortcuts.Tabs.pin, "Pin the current tab"),
        (KeyboardShortcuts.Window.newPrivate, "Slip into the shadows")
    ]

    var body: some View {
        ZStack {
            OnboardingConfetti()
            planet
                .scaleEffect(popped ? 1 : 0.6)
                .opacity(popped ? 1 : 0)
                .position(x: 400, y: 146)
            VStack(spacing: 8) {
                Text("Your planet is ready")
                    .font(.system(size: 50, weight: .black))
                    .tracking(-1)
                    .foregroundStyle(LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#FFF3E8"), location: 0.1),
                            .init(color: Color(hex: "#FFC2A0"), location: 0.55),
                            .init(color: Color(hex: "#F58AB8"), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .scaleEffect(popped ? 1 : 0.6)
                    .opacity(popped ? 1 : 0)
                    .accessibilityAddTraits(.isHeader)
                Text("Four keys to get around. The rest you'll find along the way.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingInk.muted)
            }
            .position(x: 400, y: 300)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(shortcuts, id: \.0.id) { shortcut, text in
                    keyCard(shortcut.display, text)
                }
            }
            .frame(width: 580)
            .onboardingFadeUp(delay: 0.4)
            .position(x: 400, y: 425)
        }
        .frame(width: 800, height: 600)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.9, bounce: 0.35)) { hasPopped = true }
        }
    }

    private var popped: Bool {
        hasPopped || reduceMotion
    }

    private var planet: some View {
        ZStack {
            OnboardingGlow(size: 160)
            OmbrePlanet(size: 124, shadow: OnboardingNightfall.shadow(for: .ready), ring: true)
            OnboardingClock { time in
                moons(angle: time / 14 * 360)
            }
        }
        .frame(width: 240, height: 200)
    }

    /// Three small moons, one turn every 14 seconds.
    private func moons(angle: Double) -> some View {
        ZStack {
            moon(["#9AD9FF", "#5B7BFF"], size: 14, at: angle - 90)
            moon(["#FFE29A", "#FFA35B"], size: 12, at: angle + 180)
            moon(["#B9F5D2", "#5FD39A"], size: 10, at: angle + 20)
        }
        .frame(width: 180, height: 180)
    }

    private func moon(_ colors: [String], size: CGFloat, at degrees: Double) -> some View {
        let radians = degrees * .pi / 180
        return Circle()
            .fill(LinearGradient(
                colors: colors.map(Color.init(hex:)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .shadow(color: Color(hex: colors[1]).opacity(0.8), radius: 6)
            .offset(x: 90 * cos(radians), y: 90 * sin(radians))
    }

    private func keyCard(_ key: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(OnboardingInk.dark)
                .padding(.horizontal, 8)
                .frame(minWidth: 46, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(hex: "#FFFBF7"), Color(hex: "#EDE6F7")],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .shadow(color: Color(hex: "#B9A9D9"), radius: 0, y: 3)
                )
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(OnboardingInk.light)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Confetti in the icon's colors, falling and turning.
struct OnboardingConfetti: View {
    struct Bit {
        let left: Double
        let width: Double
        let isRound: Bool
        let color: Color
        let delay: Double
        let duration: Double
    }

    static let bits: [Bit] = {
        var random = SeededRandom(seed: 29)
        let colors = ["#FFC49E", "#F06BA8", "#9AD9FF", "#B9F5D2", "#FFE29A", "#C9A6FF"].map(Color.init(hex:))
        return (0 ..< 28).map { index in
            Bit(
                left: random.next() * 790,
                width: 5 + random.next() * 6,
                isRound: random.next() > 0.5,
                color: colors[index % colors.count],
                delay: random.next() * 6,
                duration: 5 + random.next() * 3
            )
        }
    }()

    var body: some View {
        OnboardingClock { time in
            Canvas { context, _ in
                for bit in Self.bits {
                    // With Reduce Motion (time 0), the bits stay spread out.
                    let progress = ((time + bit.delay) / bit.duration).truncatingRemainder(dividingBy: 1)
                    let opacity = progress < 0.1 ? progress / 0.1 : 1 - 0.8 * (progress - 0.1) / 0.9
                    let height = bit.isRound ? bit.width : bit.width * 1.8
                    var copy = context
                    copy.opacity = opacity
                    copy.translateBy(x: bit.left, y: -40 + progress * 680)
                    copy.rotate(by: .degrees(progress * 540))
                    let rect = CGRect(x: -bit.width / 2, y: -height / 2, width: bit.width, height: height)
                    let shape = bit.isRound
                        ? Path(ellipseIn: rect)
                        : Path(roundedRect: rect, cornerRadius: 2)
                    copy.fill(shape, with: .color(bit.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
