import Foundation

/// The assistant follows an evening: each step has its sky, from golden hour
/// to a violet night, all in the same violet-pink family (never a light sky
/// nor an almost black night), more stars, and the planet's shadow a little higher,
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
        case .welcome: Sky(colors: ["#5B3FA0", "#8E4C9E", "#D2708E", "#F09C82"], locations: [0, 0.42, 0.76, 1])
        // Sunset.
        case .importZen: Sky(colors: ["#503496", "#7E4796", "#B25E88", "#CF7A84"], locations: [0, 0.45, 0.8, 1])
        // Dusk.
        case .spaces: Sky(colors: ["#42307F", "#6A3E8C", "#9E5582", "#B2647F"], locations: [0, 0.58, 0.92, 1])
        // Nightfall.
        case .protection: Sky(colors: ["#382A76", "#4A2F80", "#6A3B7C", "#7E467A"], locations: [0, 0.52, 0.86, 1])
        // Night.
        case .defaultBrowser: Sky(colors: ["#30246C", "#3C2B78", "#573576"], locations: [0, 0.5, 1])
        // Violet night.
        case .ready: Sky(colors: ["#33246F", "#251B5C", "#2E1F60"], locations: [0, 0.55, 1])
        }
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
