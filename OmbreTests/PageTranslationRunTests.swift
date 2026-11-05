import Foundation
@testable import Ombre
import Testing
import Translation

/// A page's text in memory.
@MainActor
private final class FakePage: PageTextAccess {
    var pieces: [String]
    var shown: [String: String] = [:]

    init(_ pieces: [String]) {
        self.pieces = pieces
    }

    func collectText() async -> [String] {
        pieces
    }

    func showTranslations(_ translations: [String: String]) {
        shown.merge(translations) { _, new in new }
    }
}

/// Translates into upper case; `prepare` and the groups after `hangsAfter`
/// can hang (ignoring cancellation, like a stuck service) or fail.
private final class FakeTranslator: PageTextTranslating, @unchecked Sendable {
    enum Behavior { case works, hangs, fails }

    var prepare: Behavior = .works
    var hangsAfter = Int.max
    private(set) var prepared = false
    private(set) var groups: [[PageTextPiece]] = []
    private(set) var cancelled = false

    func cancel() {
        cancelled = true
    }

    struct Declined: LocalizedError {
        var errorDescription: String? {
            "declined"
        }
    }

    private func hang() async {
        // Ignores cancellation, for a while (not forever: the test process goes on).
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func prepare() async throws {
        switch prepare {
        case .works: prepared = true
        case .hangs: await hang()
        case .fails: throw Declined()
        }
    }

    func translate(_ pieces: [PageTextPiece]) async throws -> [String: String] {
        groups.append(pieces)
        if groups.count > hangsAfter { await hang() }
        return Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0.text.uppercased()) })
    }
}

@MainActor
struct PageTranslationRunTests {
    private let pair = PageTranslationPair(
        source: Locale.Language(identifier: "de"),
        target: Locale.Language(identifier: "fr")
    )
    private let quick = PageTranslationTimeouts(prepare: 0.3, group: 0.3)

    private func run(
        _ page: FakePage,
        _ translator: FakeTranslator,
        needsDownload: Bool = false,
        keepGoing: @escaping (PageTranslationState) -> Bool = { _ in true }
    ) async -> [PageTranslationState] {
        var states: [PageTranslationState] = []
        await PageTranslationRun.run(
            pair, page: page, translator: translator, needsDownload: needsDownload, timeouts: quick
        ) { state in
            states.append(state)
            return keepGoing(state)
        }
        return states
    }

    // MARK: - Plan

    /// Each different text once (menus repeat), in small groups.
    @Test func planSendsEachTextOnceInSmallGroups() {
        let plan = PageTranslationPlan(pieces: ["Menü", "Hallo", "Menü", "", "Welt"], maxPieces: 2)
        #expect(plan.texts == ["Menü", "Hallo", "Welt"])
        #expect(plan.positions == [[0, 2], [1], [4]])
        #expect(plan.groups == [0 ..< 2, 2 ..< 3])
        #expect(plan.pieceCount == 4)
        #expect(plan.pieceCount(ofFirst: 1) == 2)
        #expect(plan.pageTranslations(["0": "Menu", "2": "Monde"]) == ["0": "Menu", "2": "Menu", "4": "Monde"])

        // A long text closes its group.
        let long = String(repeating: "a", count: 500)
        let byLength = PageTranslationPlan(pieces: ["kurz", long, "noch"], maxPieces: 10, maxCharacters: 300)
        #expect(byLength.groups == [0 ..< 1, 1 ..< 2, 2 ..< 3])
    }

    // MARK: - Runs

    /// Languages already on the Mac: translated group by group, each shown as it comes.
    @Test func installedLanguagesTranslateGroupByGroup() async {
        let page = FakePage((0 ..< 30).map { "Text \($0)" })
        let translator = FakeTranslator()
        let states = await run(page, translator)
        #expect(!translator.prepared)
        #expect(states.first == .translating(pair, done: 0, total: 30))
        #expect(states.contains(.translating(pair, done: 12, total: 30)))
        #expect(states.last == .translated(pair))
        #expect(translator.groups.count == 3)
        #expect(page.shown["29"] == "TEXT 29")
    }

    /// A language to download: macOS's prompt first, then the translation.
    @Test func aMissingLanguageIsDownloadedFirst() async {
        let page = FakePage(["Hallo"])
        let translator = FakeTranslator()
        let states = await run(page, translator, needsDownload: true)
        #expect(translator.prepared)
        #expect(states.first == .preparing(pair))
        #expect(states.last == .translated(pair))
    }

    /// The download declined or failed: said, with where to add the language.
    @Test func aDeclinedDownloadIsTold() async throws {
        let translator = FakeTranslator()
        translator.prepare = .fails
        let states = await run(FakePage(["Hallo"]), translator, needsDownload: true)
        guard case let .failed(_, message, isPartial) = try #require(states.last) else {
            Issue.record("Expected a failure, got \(states)")
            return
        }
        #expect(message.contains("declined"))
        #expect(message.contains("Translation Languages"))
        #expect(!isPartial)
    }

    /// Never waiting without end: a download that doesn't come stops with a message.
    @Test func aDownloadThatNeverComesStops() async throws {
        let translator = FakeTranslator()
        translator.prepare = .hangs
        let start = Date()
        let states = await run(FakePage(["Hallo"]), translator, needsDownload: true)
        #expect(Date().timeIntervalSince(start) < 2)
        guard case let .failed(_, message, _) = try #require(states.last) else {
            Issue.record("Expected a failure, got \(states)")
            return
        }
        #expect(message.contains("took too long"))
    }

    /// A group that never comes back: what came stays shown, with a message.
    @Test func aStuckGroupStopsWithWhatCame() async {
        let page = FakePage((0 ..< 30).map { "Text \($0)" })
        let translator = FakeTranslator()
        translator.hangsAfter = 1
        let start = Date()
        let states = await run(page, translator)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(translator.cancelled)
        #expect(page.shown["0"] == "TEXT 0")
        #expect(states.last == .failed(
            pair,
            message: "The translation took too long and was stopped. Try again.",
            isPartial: true
        ))
    }

    @Test func aPageWithoutTextIsTold() async {
        let states = await run(FakePage([]), FakeTranslator())
        #expect(states.last == .failed(pair, message: "This page has no text to translate.", isPartial: false))
    }

    /// Stopped (the original shown, another page): no further group, no message.
    @Test func aStoppedRunEndsQuietly() async {
        let translator = FakeTranslator()
        let page = FakePage((0 ..< 30).map { "Text \($0)" })
        let states = await run(page, translator) { state in
            if case let .translating(_, done, _) = state { return done == 0 }
            return true
        }
        #expect(translator.groups.count == 1)
        // The group that came after the stop isn't shown.
        #expect(page.shown.isEmpty)
        #expect(translator.cancelled)
        #expect(!states.contains { if case .failed = $0 { true } else { false } })
    }

    /// Cancelled (the page's view went): no message from the run itself.
    @Test func aCancelledRunEndsQuietly() async {
        let translator = FakeTranslator()
        translator.hangsAfter = 0
        var states: [PageTranslationState] = []
        let task = Task { @MainActor in
            await PageTranslationRun.run(
                pair, page: FakePage(["Hallo"]), translator: translator, needsDownload: false,
                timeouts: PageTranslationTimeouts(prepare: 10, group: 10)
            ) { state in
                states.append(state)
                return true
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        #expect(states == [.translating(pair, done: 0, total: 1)])
    }

    // MARK: - Time limit

    @Test func timeLimitGivesTheResultOrStops() async throws {
        #expect(try await withTimeout(seconds: 1) { 42 } == 42)
        let start = Date()
        await #expect(throws: AsyncTimeoutError.self) {
            try await withTimeout(seconds: 0.2) {
                // Ignores cancellation.
                for _ in 0 ..< 30 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        #expect(Date().timeIntervalSince(start) < 1)
        await #expect(throws: CancellationError.self) {
            let task = Task {
                try await withTimeout(seconds: 10) {
                    for _ in 0 ..< 30 {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }
            task.cancel()
            try await task.value
        }
    }

    // MARK: - Messages and settings

    @Test func messagesSayWhatFailed() {
        let unsupported = PageTranslationRun.message(for: TranslationError.unsupportedLanguagePairing, pair: pair)
        #expect(unsupported.contains("can't translate"))
        let download = PageTranslationRun.message(for: PageTranslationFailure.downloadFailed("x"), pair: pair)
        #expect(download.contains("System Settings"))
    }

    @Test func settingsAreKeptBySiteAndLanguage() throws {
        let suite = "translation-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PageTranslationSettings(defaults: defaults)
        #expect(settings.targetLanguage == PageLanguage.userLanguage)
        settings.setTargetLanguage(Locale.Language(identifier: "es"))
        #expect(settings.targetLanguage.languageCode == "es")

        let german = Locale.Language(identifier: "de-DE")
        settings.setAlwaysTranslates(german, true)
        #expect(settings.alwaysTranslates(Locale.Language(identifier: "de")))
        settings.setAlwaysTranslates(german, false)
        #expect(!settings.alwaysTranslates(german))

        settings.setNeverTranslates(host: "www.Spiegel.de", true)
        #expect(settings.neverTranslates(host: "spiegel.de"))
        #expect(!settings.neverTranslates(host: "zeit.de"))
    }
}
