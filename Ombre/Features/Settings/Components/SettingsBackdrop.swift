import AppKit
import SwiftUI

/// What the settings window shows behind its glass (macOS 26): glass needs
/// something to refract, a plain dark window leaves it gray on gray. Until
/// one is chosen, the Debug menu switches between them live.
enum SettingsBackdrop: String, CaseIterable, Identifiable {
    /// The window's background color, as before.
    case plain
    /// The desktop picture, blurred, like Finder's sidebar.
    case translucent
    /// macOS's gray window with a faint evening tint at the top, the
    /// first-launch assistant's colors.
    case gradient
    /// Translucent, with that same faint tint.
    case tintedTranslucent

    static let defaultsKey = "settings.backdrop"
    /// The gradient takes the selected space's color in Settings › Spaces.
    static let followsSpaceKey = "settings.backdrop.followsSpace"
    static let defaultValue = SettingsBackdrop.gradient

    var id: String {
        rawValue
    }

    /// Glass only exists on macOS 26: before it, the window stays plain.
    var effective: SettingsBackdrop {
        if #available(macOS 26, *) { return self }
        return .plain
    }

    var showsDesktop: Bool {
        self == .translucent || self == .tintedTranslucent
    }

    var hasGradient: Bool {
        self == .gradient || self == .tintedTranslucent
    }

    /// The Debug menu's names (the Release build sees them too, for the
    /// translation check).
    static var debugMenuTitle: String {
        String(localized: "Settings Background")
    }

    static var debugFollowsSpaceTitle: String {
        String(localized: "Space Color in Settings › Spaces")
    }

    /// Its name in the Debug menu.
    var debugTitle: String {
        switch self {
        case .plain: String(localized: "Plain (Current)")
        case .translucent: String(localized: "A · Translucent Window")
        case .gradient: String(localized: "B · Ombre Gradient")
        case .tintedTranslucent: String(localized: "C · Translucent with Ombre Tint")
        }
    }
}

/// A color as sRGB components from 0 to 1, to mix and measure the
/// backdrop's colors (WCAG contrast).
struct BackdropRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    /// From `#RRGGBB`; black if it can't be read.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
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

/// The backdrop itself, under the whole window (title bar included).
struct SettingsBackdropView: View {
    let backdrop: SettingsBackdrop
    /// The selected space's color (`#RRGGBB`), if the gradient follows it.
    var spaceHex: String?

    var body: some View {
        ZStack {
            switch backdrop.effective {
            case .plain:
                Color(nsColor: .windowBackgroundColor)
            case .translucent:
                DesktopBlur()
            case .gradient:
                Color(nsColor: .windowBackgroundColor)
                tint
            case .tintedTranslucent:
                DesktopBlur()
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

/// The desktop picture, blurred, behind the window: the sidebar material,
/// which keeps text legible over any picture.
private struct DesktopBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
