import Combine
import Foundation

/// How reader mode shows articles, the same in every window (a choice of
/// look, nothing about the sites read: kept in private windows too).
@MainActor
final class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    enum Theme: String, CaseIterable, Identifiable {
        /// Light or dark, as the Mac.
        case automatic, light, sepia, dark

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .automatic: String(localized: "reader.theme.automatic", defaultValue: "Automatic")
            case .light: String(localized: "reader.theme.light", defaultValue: "Light")
            case .sepia: String(localized: "reader.theme.sepia", defaultValue: "Sepia")
            case .dark: String(localized: "reader.theme.dark", defaultValue: "Dark")
            }
        }
    }

    enum Width: String, CaseIterable, Identifiable {
        case narrow, medium, wide

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .narrow: String(localized: "reader.width.narrow", defaultValue: "Narrow")
            case .medium: String(localized: "reader.width.medium", defaultValue: "Medium")
            case .wide: String(localized: "reader.width.wide", defaultValue: "Wide")
            }
        }

        /// The column, in characters of the text: about 60 to 80 reads best.
        var characters: Int {
            switch self {
            case .narrow: 58
            case .medium: 68
            case .wide: 82
            }
        }
    }

    enum Font: String, CaseIterable, Identifiable {
        case sans, serif

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .sans: String(localized: "reader.font.sans", defaultValue: "Sans Serif")
            case .serif: String(localized: "reader.font.serif", defaultValue: "Serif")
            }
        }
    }

    /// Text sizes, in points.
    static let sizes = [14, 16, 18, 20, 22, 25, 28, 32]
    static let defaultSize = 20

    @Published var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    @Published var width: Width {
        didSet { defaults.set(width.rawValue, forKey: Key.width) }
    }

    @Published var font: Font {
        didSet { defaults.set(font.rawValue, forKey: Key.font) }
    }

    @Published private(set) var size: Int {
        didSet { defaults.set(size, forKey: Key.size) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "reader.theme"
        static let width = "reader.width"
        static let font = "reader.font"
        static let size = "reader.size"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(Theme.init(rawValue:)) ?? .automatic
        width = defaults.string(forKey: Key.width).flatMap(Width.init(rawValue:)) ?? .medium
        font = defaults.string(forKey: Key.font).flatMap(Font.init(rawValue:)) ?? .sans
        let stored = defaults.integer(forKey: Key.size)
        size = Self.sizes.contains(stored) ? stored : Self.defaultSize
    }

    var canMakeTextBigger: Bool {
        size < Self.sizes.last ?? size
    }

    var canMakeTextSmaller: Bool {
        size > Self.sizes.first ?? size
    }

    func makeTextBigger() {
        if let next = Self.sizes.first(where: { $0 > size }) { size = next }
    }

    func makeTextSmaller() {
        if let previous = Self.sizes.last(where: { $0 < size }) { size = previous }
    }

    func resetTextSize() {
        size = Self.defaultSize
    }

    /// What the reader's document takes (see `ReaderDocument`).
    var style: ReaderDocument.Style {
        ReaderDocument.Style(theme: theme, width: width, font: font, size: size)
    }
}
