import Foundation
@testable import Ombre
import Testing
import Translation

/// A page's text in memory.
@MainActor
private final class FakePage: PageTextAccess {
    var pieces: [String]
    var shown: [String: String] = [:]
    /// What the user scrolled to, given once at the next call.
    var scrolledTo: [Int] = []

    init(_ pieces: [String]) {
        self.pieces = pieces
    }

    func collectText() async -> [String] {
        pieces
    }

    func showTranslations(_ translations: [String: String]) {
        shown.merge(translations) { _, new in new }
    }

    func piecesOnScreen() async -> [Int] {
        defer { scrolledTo = [] }
        return scrolledTo
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
        _ translator: PageTextTranslating,
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

    /// Each different text once (menus repeat).
    @Test func planTranslatesEachTextOnce() {
        let plan = PageTranslationPlan(pieces: ["Menü", "Hallo", "Menü", "", "Welt"])
        #expect(plan.texts == ["Menü", "Hallo", "Welt"])
        #expect(plan.positions == [[0, 2], [1], [4]])
        #expect(plan.textOfPiece == [0, 1, 0, nil, 2])
        #expect(plan.pieceCount == 4)
        #expect(plan.pageTranslations(["0": "Menu", "2": "Monde"]) == ["0": "Menu", "2": "Menu", "4": "Monde"])
    }

    /// A small first group (shown within a second), then bigger ones; a
    /// long text closes its group.
    @Test func queueSendsASmallFirstGroup() {
        let plan = PageTranslationPlan(pieces: (0 ..< 20).map { "Text \($0)" })
        var queue = PageTranslationQueue(plan: plan)
        #expect(queue.next() == [0, 1, 2, 3])
        #expect(queue.next() == Array(4 ..< 16))
        #expect(queue.donePieces == 16)
        #expect(queue.next() == Array(16 ..< 20))
        #expect(queue.isEmpty)

        let long = String(repeating: "a", count: 500)
        var byLength = PageTranslationQueue(plan: PageTranslationPlan(pieces: ["kurz", long, "noch"]))
        byLength.firstGroup = (pieces: 10, characters: 300)
        byLength.group = (pieces: 10, characters: 300)
        #expect(byLength.next() == [0])
        #expect(byLength.next() == [1])
        #expect(byLength.next() == [2])
    }

    /// The text scrolled to comes first (piece numbers, a repeated text
    /// once); the texts already known never.
    @Test func queueTakesTheTextOnScreenFirst() {
        let plan = PageTranslationPlan(pieces: (0 ..< 30).map { "Text \($0 % 25)" })
        var queue = PageTranslationQueue(plan: plan, done: [1])
        #expect(queue.next() == [0, 2, 3, 4])
        // Piece 28 shows text 3 (sent already), piece 1 is known: only
        // text 20 comes first, then the queue's order.
        #expect(queue.next(onScreen: [28, 3, 20, 1]) == [20] + Array(5 ... 15))
        #expect(queue.next(onScreen: [999]) == Array(16 ... 19) + Array(21 ... 24))
        #expect(queue.isEmpty)

        // More on screen than one group: the rest of the screen comes next.
        let long = PageTranslationPlan(pieces: (0 ..< 60).map { "Text \($0)" })
        var scrolled = PageTranslationQueue(plan: long)
        _ = scrolled.next()
        #expect(scrolled.next(onScreen: Array(30 ..< 50)) == Array(30 ..< 42))
        #expect(scrolled.next() == Array(42 ..< 50) + Array(4 ..< 8))
    }

    // MARK: - Runs

    /// Languages already on the Mac: translated group by group, each shown as it comes.
    @Test func installedLanguagesTranslateGroupByGroup() async {
        let page = FakePage((0 ..< 30).map { "Text \($0)" })
        let translator = FakeTranslator()
        let states = await run(page, translator)
        #expect(!translator.prepared)
        #expect(states.first == .translating(pair, done: 0, total: 30))
        #expect(states.contains(.translating(pair, done: 4, total: 30)))
        #expect(states.contains(.translating(pair, done: 16, total: 30)))
        #expect(states.last == .translated(pair))
        #expect(translator.groups.count == 4)
        #expect(page.shown["29"] == "TEXT 29")
    }

    /// Translated again from the page's memory: all shown at once, nothing
    /// asked, no progress shown.
    @Test func theMemoryIsShownAtOnce() async {
        let page = FakePage(["Hallo", "Welt", "Hallo"])
        let base = FakeTranslator()
        let memory = PageTranslationMemory(pair: pair)
        memory.remember("Hallo", as: "Bonjour")
        memory.remember("Welt", as: "Monde")
        let states = await run(page, MemorizingTranslator(base: base, memory: memory))
        #expect(states == [.translating(pair, done: 0, total: 3), .translated(pair)])
        #expect(base.groups.isEmpty)
        #expect(page.shown == ["0": "Bonjour", "1": "Monde", "2": "Bonjour"])
    }

    /// Half known: the known part shown first, only the rest asked.
    @Test func onlyWhatTheMemoryLacksIsAsked() async {
        let page = FakePage(["Hallo", "Welt"])
        let base = FakeTranslator()
        let memory = PageTranslationMemory(pair: pair)
        memory.remember("Hallo", as: "Bonjour")
        let states = await run(page, MemorizingTranslator(base: base, memory: memory))
        #expect(states.prefix(2) == [.translating(pair, done: 0, total: 2), .translating(pair, done: 1, total: 2)])
        #expect(base.groups == [[PageTextPiece(id: "1", text: "Welt")]])
        #expect(page.shown == ["0": "Bonjour", "1": "WELT"])
    }

    /// The user scrolls down: the text now on screen is translated next.
    @Test func theTextScrolledToComesNext() async {
        let page = FakePage((0 ..< 40).map { "Text \($0)" })
        let translator = FakeTranslator()
        _ = await run(page, translator) { state in
            if case .translating(_, 4, _) = state { page.scrolledTo = [38, 39] }
            return true
        }
        #expect(translator.groups.count > 1)
        #expect(translator.groups[1].prefix(2).map(\.id) == ["38", "39"])
        #expect(page.shown.count == 40)
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
