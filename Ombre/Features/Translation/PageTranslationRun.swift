import Foundation
import os
import Translation

private let logger = Logger(category: "Translation")

/// The page's text, read and changed by its translator script (see
/// `PageTranslatorScript`).
@MainActor
protocol PageTextAccess: AnyObject {
    /// The page's pieces of text, the visible ones first.
    func collectText() async -> [String]
    /// Translations by piece number.
    func showTranslations(_ translations: [String: String])
    /// The pieces on screen not translated yet, once the user scrolled since
    /// the last call (else none: the queue's order stands).
    func piecesOnScreen() async -> [Int]
}

/// What translates text: Apple's Translation, on the Mac (see
/// `SessionTextTranslator`).
protocol PageTextTranslating {
    /// Makes sure both languages are on the Mac: macOS asks the user to
    /// download what's missing (its own prompt), and returns once it is.
    func prepare() async throws
    /// Translations by piece id.
    func translate(_ pieces: [PageTextPiece]) async throws -> [String: String]
    /// The translations already known for `pieces` (the page's memory), by
    /// piece id: shown at once, never asked again.
    func remembered(_ pieces: [PageTextPiece]) async -> [String: String]
    /// Stops what is still at work (after a time limit, or when stopped).
    func cancel()
}

extension PageTextTranslating {
    func remembered(_: [PageTextPiece]) async -> [String: String] {
        [:]
    }
}

/// How long each step may take before the translation stops with a message:
/// never a button turning forever.
struct PageTranslationTimeouts {
    /// The user answers macOS's prompt and the language downloads.
    var prepare: Double = 300
    /// A group of pieces: usually a few seconds.
    var group: Double = 45

    static let standard = PageTranslationTimeouts()
}

enum PageTranslationFailure: Error, Equatable {
    case nothingToTranslate
    /// The language download didn't finish (declined, failed, too long).
    case downloadFailed(String)
}

/// One translation of a page: downloads the languages if needed, shows at
/// once what the page's memory knows, then translates the rest in small
/// groups (see `PageTranslationQueue`), the text on screen first, showing
/// each as it comes. `update` gets each new state and returns false once
/// the run is no longer the page's (stopped, another page): it then ends
/// quietly.
@MainActor
enum PageTranslationRun {
    static func run(
        _ pair: PageTranslationPair,
        page: PageTextAccess,
        translator: PageTextTranslating,
        needsDownload: Bool,
        timeouts: PageTranslationTimeouts = .standard,
        update: (PageTranslationState) -> Bool
    ) async {
        let start = Date()
        let languages = "\(pair.source.minimalIdentifier) → \(pair.target.minimalIdentifier)"
        logger.notice("Translating \(languages, privacy: .public), download needed: \(needsDownload)")
        var shown = 0
        do {
            if needsDownload {
                guard update(.preparing(pair)) else { return }
                try await prepare(with: translator, timeout: timeouts.prepare)
                let ready = elapsed(since: start)
                logger.notice("Languages ready for \(languages, privacy: .public) after \(ready, privacy: .public) s")
            }
            let plan = await PageTranslationPlan(pieces: page.collectText())
            let found = "\(plan.pieceCount) pieces, \(plan.texts.count) different"
            logger.notice("\(found, privacy: .public) (\(elapsed(since: start), privacy: .public) s)")
            guard !plan.texts.isEmpty else { throw PageTranslationFailure.nothingToTranslate }
            let total = plan.pieceCount

            var queue = await showRemembered(plan, page: page, translator: translator, since: start)
            shown = queue.donePieces
            guard !queue.isEmpty else {
                logger.notice("Translated from memory in \(elapsed(since: start), privacy: .public) s")
                _ = update(.translated(pair))
                return
            }
            guard update(.translating(pair, done: shown, total: total)) else { return }
            var firstShown = shown > 0
            while !queue.isEmpty {
                let group = await queue.next(onScreen: page.piecesOnScreen())
                let translations = try await withTimeout(seconds: timeouts.group) {
                    try await translator.translate(plan.pieces(of: group))
                }
                guard !Task.isCancelled else { throw CancellationError() }
                let done = queue.donePieces
                // Still this page's translation: only then shown.
                guard update(.translating(pair, done: done, total: total)) else {
                    logger.notice("Translation stopped after \(shown) of \(total) pieces")
                    translator.cancel()
                    return
                }
                page.showTranslations(plan.pageTranslations(translations))
                if !firstShown {
                    firstShown = true
                    logger.notice("First translations shown after \(elapsed(since: start), privacy: .public) s")
                }
                shown = done
            }
            logger.notice("Translated \(total) pieces in \(elapsed(since: start), privacy: .public) s")
            _ = update(.translated(pair))
        } catch {
            translator.cancel()
            // Stopped by the user or the page going: nothing to tell.
            guard !Task.isCancelled else {
                logger.notice("Translation cancelled after \(shown) pieces")
                return
            }
            logger.error(
                "Translation failed after \(shown) pieces: \(String(describing: error), privacy: .public)"
            )
            _ = update(.failed(pair, message: message(for: error, pair: pair), isPartial: shown > 0))
        }
    }

    /// What the page's memory knows, shown at once, in one go: the queue of
    /// the rest.
    private static func showRemembered(
        _ plan: PageTranslationPlan,
        page: PageTextAccess,
        translator: PageTextTranslating,
        since start: Date
    ) async -> PageTranslationQueue {
        let known = await translator.remembered(plan.pieces(of: Array(plan.texts.indices)))
        guard !known.isEmpty else { return PageTranslationQueue(plan: plan) }
        page.showTranslations(plan.pageTranslations(known))
        let remembered = "\(known.count) texts from memory"
        logger.notice("\(remembered, privacy: .public) shown after \(elapsed(since: start), privacy: .public) s")
        return PageTranslationQueue(plan: plan, done: Set(known.keys.compactMap(Int.init)))
    }

    /// Seconds since `start`, for the logs.
    private static func elapsed(since start: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(start))
    }

    private static func prepare(with translator: PageTextTranslating, timeout: Double) async throws {
        logger.info("Asking macOS to download the languages")
        do {
            try await withTimeout(seconds: timeout) { try await translator.prepare() }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            logger.error("Language download failed: \(String(describing: error), privacy: .public)")
            throw PageTranslationFailure.downloadFailed(
                error is AsyncTimeoutError ? "it took too long" : error.localizedDescription
            )
        }
    }

    /// What the panel tells about `error`, in plain words.
    static func message(for error: Error, pair: PageTranslationPair) -> String {
        let source = PageLanguage.name(of: pair.source)
        let target = PageLanguage.name(of: pair.target)
        switch error {
        case PageTranslationFailure.nothingToTranslate, TranslationError.nothingToTranslate:
            return "This page has no text to translate."
        case let PageTranslationFailure.downloadFailed(reason):
            return "macOS didn't download \(source) for translation (\(reason)). "
                + "You can add it in System Settings › General › Language & Region › Translation Languages."
        case is AsyncTimeoutError:
            return "The translation took too long and was stopped. Try again."
        case TranslationError.unsupportedLanguagePairing, TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage:
            return "macOS can't translate \(source) into \(target)."
        case TranslationError.unableToIdentifyLanguage:
            return "macOS couldn't tell which language this page is in."
        default:
            return "The page couldn't be translated: \(error.localizedDescription)"
        }
    }
}

/// Apple's Translation, on the Mac (nothing sent away).
struct SessionTextTranslator: PageTextTranslating {
    let session: TranslationSession

    func prepare() async throws {
        try await session.prepareTranslation()
    }

    func cancel() {
        if #available(macOS 26.0, *) { session.cancel() }
    }

    func translate(_ pieces: [PageTextPiece]) async throws -> [String: String] {
        let requests = pieces.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
        var translations: [String: String] = [:]
        for response in try await session.translations(from: requests) {
            if let id = response.clientIdentifier { translations[id] = response.targetText }
        }
        return translations
    }
}
