import Foundation

/// Where the page's translation stands, for the address bar's button.
enum PageTranslationState: Equatable {
    /// Same language as the Mac's, or one that can't be translated.
    case unavailable
    /// In another language: the button offers to translate it.
    case offered(from: Locale.Language)
    case translating(from: Locale.Language)
    /// Shown translated: the button shows the original again.
    case translated(from: Locale.Language)

    var sourceLanguage: Locale.Language? {
        switch self {
        case .unavailable: nil
        case let .offered(language), let .translating(language), let .translated(language): language
        }
    }
}
