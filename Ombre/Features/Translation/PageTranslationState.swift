import Foundation
import Translation

/// The languages a page is translated from and into.
struct PageTranslationPair: Equatable {
    let source: Locale.Language
    let target: Locale.Language
}

/// Where the page's translation stands, for the address bar's button and
/// the translation panel.
enum PageTranslationState: Equatable {
    /// Shown as the page wrote it.
    case original
    /// Waiting for macOS to download a language (its prompt is shown).
    case preparing(PageTranslationPair)
    /// `done` of `total` pieces of text shown translated so far.
    case translating(PageTranslationPair, done: Int, total: Int)
    /// Shown translated: the original is a click away.
    case translated(PageTranslationPair)
    /// Stopped by an error; what was already translated stays shown
    /// (`isPartial`), with the original a click away.
    case failed(PageTranslationPair, message: String, isPartial: Bool)

    var pair: PageTranslationPair? {
        switch self {
        case .original: nil
        case let .preparing(pair), let .translating(pair, _, _), let .translated(pair), let .failed(pair, _, _): pair
        }
    }

    /// Still working: the button turns and the panel offers to stop.
    var isBusy: Bool {
        switch self {
        case .preparing, .translating: true
        default: false
        }
    }

    /// The share of the page translated so far, from 0 to 1, while it is
    /// translated (none before the text is counted, or once done).
    var progress: Double? {
        guard case let .translating(_, done, total) = self, total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// `progress` in whole percents, for the button's tooltip and the panel.
    var percentDone: Int? {
        progress.map { Int(($0 * 100).rounded(.down)) }
    }

    /// Waiting for a language download.
    var isPreparing: Bool {
        if case .preparing = self { true } else { false }
    }

    /// Some of the page shows translated text.
    var showsTranslation: Bool {
        switch self {
        case .original, .preparing: false
        case let .translating(_, done, _): done > 0
        case .translated: true
        case let .failed(_, _, isPartial): isPartial
        }
    }
}

/// A translation that needs a session from the page's view (see
/// `PageTranslationHost`): to show macOS's prompt to download a language,
/// or before macOS 26 (no session without a view).
struct PageTranslationRequest: Equatable {
    let id: UUID
    let pair: PageTranslationPair
    let needsDownload: Bool
    /// Alternates from one request to the next (see `configuration`).
    var version = 0

    /// What starts the view's task: never equal to the previous request's.
    var configuration: TranslationSession.Configuration {
        var configuration = TranslationSession.Configuration(source: pair.source, target: pair.target)
        if version == 1 { configuration.invalidate() }
        return configuration
    }
}
