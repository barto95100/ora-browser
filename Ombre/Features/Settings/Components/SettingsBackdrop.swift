import SwiftUI

/// A color as sRGB components from 0 to 1, to mix and measure the
/// backdrop's colors (WCAG contrast).
struct BackdropRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    /// From `#RRGGBB`; black if it can't be read.
    init(hex: String) {
        // `#RRGGBBAA` too: its alpha is left out.
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(6)
        let value = UInt32(digits, radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `fraction` of the way to `other`.
    func mixed(with other: BackdropRGB, by fraction: Double) -> BackdropRGB {
        BackdropRGB(
            red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction
        )
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 to 21.
    func contrast(with other: BackdropRGB) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

/// The gradient: macOS's own gray window, with only a faint evening tint
/// at the top (violet at the left, peach at the right) that fades out
/// before the middle. Never a flat violet.
enum SettingsBackdropPalette {
    /// The tint's colors, left to right.
    static let ombreTint = ["#6A4BC4", "#F09C82"].map(BackdropRGB.init(hex:))
    /// How much of the tint shows, at the very top: 8 to 12 %.
    static let tintOpacity = 0.1
    static let spaceTintOpacity = 0.12
    /// macOS's window background, which the tint lies on (in the window,
    /// the system's own color is used).
    static let darkWindow = BackdropRGB(hex: "#1E1E1E")
    static let lightWindow = BackdropRGB(hex: "#ECECEC")

    /// The tint's colors: the evening's, or with `spaceHex` that space's.
    static func tint(spaceHex: String? = nil) -> [BackdropRGB] {
        guard let spaceHex else { return ombreTint }
        let space = BackdropRGB(hex: spaceHex)
        return [space, space.mixed(with: ombreTint[1], by: 0.35)]
    }

    static func opacity(followingSpace: Bool) -> Double {
        followingSpace ? spaceTintOpacity : tintOpacity
    }

    /// The tint's colors as they show over the window, where it is
    /// strongest: what text must stay legible on.
    static func strongest(isDark: Bool, spaceHex: String? = nil) -> [BackdropRGB] {
        let window = isDark ? darkWindow : lightWindow
        let opacity = opacity(followingSpace: spaceHex != nil)
        return tint(spaceHex: spaceHex).map { window.mixed(with: $0, by: opacity) }
    }
}

/// Tells the window's backdrop which space Settings › Spaces shows.
struct SettingsSpaceColorKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

/// What the settings window shows behind its glass: macOS's gray window
/// with a faint evening tint along the top (in Settings › Spaces, the
/// selected space's color), so the glass has something to refract. Without
/// glass (macOS 15, Glass Effects off, Reduce Transparency), the plain window.
struct SettingsBackdropView: View {
    /// The selected space's color (`#RRGGBB`), in Settings › Spaces.
    var spaceHex: String?
    @Environment(\.usesGlassEffects) private var usesGlass

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if usesGlass {
                tint
            }
        }
        .animation(.easeInOut(duration: 0.35), value: spaceHex)
        .ignoresSafeArea()
    }

    /// The faint tint along the top, fading out before the middle.
    private var tint: some View {
        let colors = SettingsBackdropPalette.tint(spaceHex: spaceHex).map(\.color)
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
            .opacity(SettingsBackdropPalette.opacity(followingSpace: spaceHex != nil))
            .allowsHitTesting(false)
    }
}
