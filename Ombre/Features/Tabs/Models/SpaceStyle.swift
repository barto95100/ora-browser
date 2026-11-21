import SwiftUI

/// Color of a space, like Arc: tints its icon, its active tab and the window
/// background (see `Theme.spaceColor`). Stored by name, so the shades can be
/// tuned without touching saved spaces.
enum SpaceColor: String, CaseIterable, Identifiable {
    case gray
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal

    var id: String {
        rawValue
    }

    /// Its color as `#RRGGBB`.
    var hex: String {
        switch self {
        case .gray: "#9A9CA3"
        case .blue: "#5BAEEF"
        case .indigo: "#8B8FEA"
        case .purple: "#B585DE"
        case .pink: "#EE87B2"
        case .red: "#EC6F6A"
        case .orange: "#F5A05A"
        case .yellow: "#E3BC57"
        case .green: "#6FC17E"
        case .teal: "#5ABFC6"
        }
    }

    var color: Color {
        Color(hex: hex)
    }

    var title: String {
        switch self {
        case .gray: String(localized: "Gray")
        case .blue: String(localized: "Blue")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .teal: String(localized: "Teal")
        }
    }
}

/// Symbols a space can use as its icon, instead of an emoji.
enum SpaceIcon {
    static let symbols = [
        "globe", "briefcase", "house", "chevron.left.forwardslash.chevron.right", "paintpalette",
        "book.closed", "graduationcap", "music.note", "camera", "gamecontroller",
        "cup.and.saucer", "leaf", "heart", "star", "sparkles",
        "airplane", "bag", "dumbbell", "lightbulb", "moon"
    ]
}

/// A dark theme for a space, like Arc's: the window background and an
/// accent. A space with a theme is always shown dark.
enum SpaceTheme: String, CaseIterable, Identifiable {
    case graphite
    case midnight
    case mocha
    case slate
    case plum
    case lavender
    case ember
    case rose
    case solarized
    case indigo
    case sage
    case ocean

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .graphite: String(localized: "Graphite")
        case .midnight: String(localized: "Midnight")
        case .mocha: String(localized: "Mocha")
        case .slate: String(localized: "Slate")
        case .plum: String(localized: "Plum")
        case .lavender: String(localized: "Lavender")
        case .ember: String(localized: "Ember")
        case .rose: String(localized: "Rosé")
        case .solarized: String(localized: "Solarized")
        case .indigo: String(localized: "Indigo")
        case .sage: String(localized: "Sage")
        case .ocean: String(localized: "Ocean")
        }
    }

    /// Its background, `#RRGGBB`.
    var backgroundHex: String {
        switch self {
        case .graphite: "#1E1F22"
        case .midnight: "#15182B"
        case .mocha: "#2A211C"
        case .slate: "#262B33"
        case .plum: "#251C2E"
        case .lavender: "#2A2836"
        case .ember: "#2B1D19"
        case .rose: "#2B1E25"
        case .solarized: "#12313A"
        case .indigo: "#1C1D33"
        case .sage: "#222823"
        case .ocean: "#0F1C2B"
        }
    }

    var background: Color {
        Color(hex: backgroundHex)
    }

    /// Its accent, `#RRGGBB`.
    var accentHex: String {
        switch self {
        case .graphite: "#E8E8E8"
        case .midnight: "#7C8CF8"
        case .mocha: "#E0975F"
        case .slate: "#7FC4D8"
        case .plum: "#C58BE8"
        case .lavender: "#B9A6F2"
        case .ember: "#F07A3C"
        case .rose: "#F2A1B6"
        case .solarized: "#268BD2"
        case .indigo: "#8C9EFF"
        case .sage: "#A9C48A"
        case .ocean: "#4D9BF0"
        }
    }

    var accent: Color {
        Color(hex: accentHex)
    }
}

extension TabContainer {
    var spaceColor: SpaceColor? {
        colorName.flatMap(SpaceColor.init(rawValue:))
    }

    var spaceTheme: SpaceTheme? {
        themeName.flatMap(SpaceTheme.init(rawValue:))
    }
}
