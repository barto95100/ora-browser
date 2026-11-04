import Foundation

/// The assistant follows an evening: each step has its sky, from golden hour
/// to a violet night, more stars, and the planet's shadow a little higher,
/// until it looks exactly like the icon.
enum OnboardingNightfall {
    /// A sky from top to bottom: colors as `#RRGGBB` and where they sit.
    struct Sky: Equatable {
        let colors: [String]
        let locations: [Double]
    }

    static func sky(for step: OnboardingStep) -> Sky {
        switch step {
        // Golden hour.
        case .welcome: Sky(colors: ["#CBB6F0", "#F2B3CF", "#FFD0B2", "#FFE8D4"], locations: [0, 0.42, 0.72, 1])
        // Sunset.
        case .importZen: Sky(colors: ["#5A3394", "#9C4690", "#D9677A", "#F09A7A"], locations: [0, 0.45, 0.78, 1])
        // Dusk.
        case .spaces: Sky(colors: ["#3B2A7A", "#4A2C78", "#5A2F6E", "#6E3A6A"], locations: [0, 0.35, 0.8, 1])
        // Nightfall.
        case .protection: Sky(colors: ["#161046", "#2A1B66", "#4E2A72", "#7A3A6E"], locations: [0, 0.5, 0.82, 1])
        // Night.
        case .defaultBrowser: Sky(colors: ["#1B1150", "#2C1C70", "#21165A", "#170F44"], locations: [0, 0.4, 0.75, 1])
        // Violet night.
        case .ready: Sky(colors: ["#25115C", "#1B0C4C", "#13083E", "#200D46"], locations: [0, 0.35, 0.75, 1])
        }
    }

    /// Only the welcome sky is light: its text is dark.
    static func isLight(_ step: OnboardingStep) -> Bool {
        step == .welcome
    }

    /// How many of the star field's stars show: none at golden hour, many
    /// at night.
    static func starCount(for step: OnboardingStep) -> Int {
        switch step {
        case .welcome: 0
        case .importZen: 6
        case .spaces: 12
        case .protection: 24
        case .defaultBrowser: 50
        case .ready: starField.count
        }
    }

    /// The planet's shadow: 0 in full sun, 1 exactly like the icon.
    static func shadow(for step: OnboardingStep) -> Double {
        switch step {
        case .welcome: 0
        case .importZen: 0.35
        case .spaces: 0.55
        case .protection: 0.75
        case .defaultBrowser: 0.9
        case .ready: 1
        }
    }

    // MARK: - Stars

    /// A star, in fractions of the window.
    struct Star: Equatable {
        let left: Double
        let top: Double
        /// In points.
        let size: Double
        /// Where it is in its twinkle, from 0 to 1.
        let phase: Double
    }

    /// The same stars every time; the first ones show first.
    static let starField: [Star] = {
        var random = SeededRandom(seed: 71)
        return (0 ..< 80).map { _ in
            Star(
                left: random.next(),
                // More stars high in the sky than near the horizon.
                top: pow(random.next(), 1.4) * 0.92,
                size: 1 + random.next() * 1.8,
                phase: random.next()
            )
        }
    }()

    /// How visible star `index` is while `shown` stars show (fractional
    /// while the count changes: the stars come out one after the other).
    static func visibility(ofStar index: Int, shown: Double) -> Double {
        min(max(shown - Double(index), 0), 1)
    }

    /// A star's twinkle at `time` (seconds): between 0.2 and 1, every 3.4 s.
    static func twinkle(_ star: Star, at time: TimeInterval) -> Double {
        let cycle = (time / 3.4 + star.phase) * 2 * .pi
        return 0.6 - 0.4 * cos(cycle)
    }
}

/// A small repeatable random generator (the stars and confetti stay put).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// The next value, from 0 up to 1.
    mutating func next() -> Double {
        // SplitMix64.
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
