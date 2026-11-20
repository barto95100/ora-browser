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
    /// A soft evening gradient, the first-launch assistant's colors.
    case gradient
    /// Translucent, tinted with that gradient.
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

/// The gradient's colors, top to bottom: violet to peach (a dusky rose in
/// dark mode), never white nor black. Secondary text stays as legible as on
/// macOS's own window in light mode, and passes WCAG AA in dark mode.
enum SettingsBackdropPalette {
    static let darkStops = ["#251B50", "#342764", "#482E62", "#52314C"].map(BackdropRGB.init(hex:))
    static let lightStops = ["#ECE5F8", "#F0E6F4", "#F6E8EC", "#FBEBE0"].map(BackdropRGB.init(hex:))
    /// What a space's color is mixed with to stay this soft.
    static let darkBase = BackdropRGB(hex: "#1A1230")
    static let lightBase = BackdropRGB(hex: "#FBF6F2")

    /// The stops; with `spaceHex`, they lean to that space's color.
    static func stops(isDark: Bool, spaceHex: String? = nil) -> [BackdropRGB] {
        let stops = isDark ? darkStops : lightStops
        guard let spaceHex else { return stops }
        let space = BackdropRGB(hex: spaceHex)
        let base = isDark ? darkBase : lightBase
        // Its color at the top, fading into the evening's peach below.
        let top = space.mixed(with: base, by: isDark ? 0.78 : 0.84)
        return [top, top.mixed(with: stops[2], by: 0.5), stops[2], stops[3]]
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch backdrop.effective {
            case .plain:
                Color(nsColor: .windowBackgroundColor)
            case .translucent:
                DesktopBlur()
            case .gradient:
                gradient
            case .tintedTranslucent:
                DesktopBlur()
                gradient.opacity(0.55)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: spaceHex)
        .ignoresSafeArea()
    }

    private var gradient: LinearGradient {
        let stops = SettingsBackdropPalette.stops(isDark: colorScheme == .dark, spaceHex: spaceHex)
        return LinearGradient(colors: stops.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
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
