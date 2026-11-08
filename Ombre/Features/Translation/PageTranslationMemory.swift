import Foundation
import Translation

/// The translations already made for a page, by text: showing the original
/// and translating again (or reloading the page) is instant, and a
/// translation stopped half way goes on from where it was. One per page and
/// language pair, for the tab's last few pages (see
/// `TabRuntime.translationMemory`). Bounded: a page that keeps adding text
/// (an endless feed) starts over past a limit.
@MainActor
final class PageTranslationMemory {
    static let maxTexts = 5000

    let pair: PageTranslationPair
    /// The page's address, without its fragment.
    let page: URL?
    private(set) var translations: [String: String] = [:]

    init(pair: PageTranslationPair, page: URL? = nil) {
        self.pair = pair
        self.page = page
    }

    func remember(_ text: String, as translation: String) {
        if translations.count >= Self.maxTexts { translations.removeAll(keepingCapacity: true) }
        translations[text] = translation
    }
}

/// Translates only the text the page's memory doesn't know yet.
struct MemorizingTranslator: PageTextTranslating {
    let base: PageTextTranslating
    let memory: PageTranslationMemory

    func prepare() async throws {
        try await base.prepare()
    }

    func cancel() {
        base.cancel()
    }

    func remembered(_ pieces: [PageTextPiece]) async -> [String: String] {
        let memory = memory
        return await MainActor.run {
            var known: [String: String] = [:]
            for piece in pieces {
                if let translation = memory.translations[piece.text] { known[piece.id] = translation }
            }
            return known
        }
    }

    func translate(_ pieces: [PageTextPiece]) async throws -> [String: String] {
        let memory = memory
        // The memory lives on the main thread; the translation doesn't.
        let (known, missing) = await MainActor.run {
            var known: [String: String] = [:]
            var missing: [PageTextPiece] = []
            for piece in pieces {
                if let translation = memory.translations[piece.text] {
                    known[piece.id] = translation
                } else {
                    missing.append(piece)
                }
            }
            return (known, missing)
        }
        guard !missing.isEmpty else { return known }
        let new = try await base.translate(missing)
        return await MainActor.run {
            var translations = known
            for piece in missing {
                guard let translation = new[piece.id] else { continue }
                memory.remember(piece.text, as: translation)
                translations[piece.id] = translation
            }
            return translations
        }
    }
}

/// Language pairs macOS said it has (`LanguageAvailability`): asked once per
/// launch, not before each translation. A pair removed in System Settings
/// since is forgotten when its translation fails.
@MainActor
enum InstalledTranslationLanguages {
    private static var installed: [PageTranslationPair] = []

    /// macOS's answer, at once for a pair known installed.
    static func status(
        of pair: PageTranslationPair,
        timeout: Double = 15,
        ask: @escaping @Sendable (PageTranslationPair) async -> LanguageAvailability.Status = askMacOS
    ) async throws -> LanguageAvailability.Status {
        if installed.contains(pair) { return .installed }
        let status = try await withTimeout(seconds: timeout) { await ask(pair) }
        if status == .installed, !installed.contains(pair) { installed.append(pair) }
        return status
    }

    static func forget(_ pair: PageTranslationPair) {
        installed.removeAll { $0 == pair }
    }

    static func forgetAll() {
        installed = []
    }

    private static func askMacOS(_ pair: PageTranslationPair) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: pair.source, to: pair.target)
    }
}
