import Foundation
@testable import Ombre
import Testing
import Translation

/// What a page's translation keeps, so translating again is instant.
@MainActor
@Suite(.serialized)
struct PageTranslationMemoryTests {
    private let pair = PageTranslationPair(
        source: Locale.Language(identifier: "de"),
        target: Locale.Language(identifier: "fr")
    )

    private final class Counting: PageTextTranslating, @unchecked Sendable {
        var asked: [[String]] = []
        func prepare() async throws {}
        func cancel() {}
        func translate(_ pieces: [PageTextPiece]) async throws -> [String: String] {
            asked.append(pieces.map(\.text))
            return Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, "fr:" + $0.text) })
        }
    }

    @Test
    func onlyNewTextIsTranslated() async throws {
        let base = Counting()
        let translator = MemorizingTranslator(base: base, memory: PageTranslationMemory(pair: pair))
        let first = try await translator.translate([PageTextPiece(id: "1", text: "Hallo")])
        #expect(first == ["1": "fr:Hallo"])
        let second = try await translator.translate([
            PageTextPiece(id: "7", text: "Hallo"),
            PageTextPiece(id: "8", text: "Welt")
        ])
        #expect(second == ["7": "fr:Hallo", "8": "fr:Welt"])
        let third = try await translator.translate([PageTextPiece(id: "9", text: "Welt")])
        #expect(third == ["9": "fr:Welt"])
        #expect(base.asked == [["Hallo"], ["Welt"]])
    }

    /// macOS is asked once whether it has the languages, while they are there.
    @Test
    func installedLanguagesAreAskedOnce() async throws {
        InstalledTranslationLanguages.forgetAll()
        defer { InstalledTranslationLanguages.forgetAll() }
        let asked = Asked()
        let installed: @Sendable (PageTranslationPair) async -> LanguageAvailability.Status = { _ in
            await asked.add()
            return .installed
        }
        for _ in 0 ..< 3 {
            #expect(try await InstalledTranslationLanguages.status(of: pair, ask: installed) == .installed)
        }
        #expect(await asked.count == 1)

        // Failing since (removed in System Settings): asked again.
        InstalledTranslationLanguages.forget(pair)
        _ = try await InstalledTranslationLanguages.status(of: pair, ask: installed)
        #expect(await asked.count == 2)
    }

    /// A language still to download is asked about each time.
    @Test
    func languagesToDownloadAreAskedEachTime() async throws {
        InstalledTranslationLanguages.forgetAll()
        defer { InstalledTranslationLanguages.forgetAll() }
        let asked = Asked()
        let supported: @Sendable (PageTranslationPair) async -> LanguageAvailability.Status = { _ in
            await asked.add()
            return .supported
        }
        for _ in 0 ..< 2 {
            #expect(try await InstalledTranslationLanguages.status(of: pair, ask: supported) == .supported)
        }
        #expect(await asked.count == 2)
    }

    private actor Asked {
        var count = 0
        func add() {
            count += 1
        }
    }
}
