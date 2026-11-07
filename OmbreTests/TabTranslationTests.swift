import AppKit
import Foundation
@testable import Ombre
import Testing
import Translation
import WebKit

extension TabManagerTests {
    /// Translating a tab's page: with a stand-in translator, then with
    /// Apple's own (a language on the Mac, and one to download).
    @MainActor
    struct TabTranslation {
        private static let german = """
        <html lang="de"><body><h1 id="a">Guten Morgen</h1><p id="b">Wie geht es dir heute?</p></body></html>
        """

        /// A tab showing `html`, its translator script ready.
        private func tab(showing html: String, in window: TabManagerTestWindow) async throws -> Tab {
            let tab = try await window.openLoaded("page")
            let page = try #require(tab.browserPage)
            tab.runtime?.clearNavigationFailure()
            var isReady = false
            // Loaded again if the failed load of the tab's address replaced it.
            for attempt in 0 ..< 200 where !isReady {
                if attempt % 40 == 0 {
                    page.extensionWebView.loadHTMLString(html, baseURL: URL(string: "https://example.com/"))
                }
                try await Task.sleep(for: .milliseconds(50))
                isReady = await evaluate(page, "window.__translator && document.getElementById('a') ? 1 : 0") as? Int ==
                    1
            }
            try #require(isReady)
            tab.runtime?.pageLanguage = Locale.Language(identifier: "de")
            return tab
        }

        private func evaluate(_ page: BrowserPage, _ script: String) async -> Any? {
            await withCheckedContinuation { continuation in
                page.evaluateJavaScript(script) { value, _ in continuation.resume(returning: value) }
            }
        }

        private func text(_ tab: Tab, _ id: String) async -> String? {
            guard let page = tab.browserPage else { return nil }
            return await evaluate(page, "document.getElementById('\(id)').textContent") as? String
        }

        private func waitUntilSettled(_ runtime: TabRuntime, seconds: Double = 5) async throws {
            let end = Date().addingTimeInterval(seconds)
            while runtime.translation.isBusy || runtime.translation == .original, Date() < end {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        @Test func pageIsTranslatedThenShownAsWritten() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                let pair = PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: Locale.Language(identifier: "fr")
                )
                let runID = UUID()
                runtime.translationRunID = runID
                await tab.runTranslation(pair, translator: UpperCase(), needsDownload: false, runID: runID)
                #expect(runtime.translation == .translated(pair))
                #expect(await text(tab, "a") == "GUTEN MORGEN")

                tab.showOriginalPage()
                #expect(runtime.translation == .original)
                #expect(await text(tab, "a") == "Guten Morgen")

                tab.destroyWebView()
                #expect(runtime.translation == .original)
                #expect(runtime.pageLanguage == nil)
            }
        }

        /// The page's context menu: translate, or the original again; the panel.
        @Test func contextMenuOffersTranslationOrTheOriginal() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                let target = PageTranslationSettings.standard.targetLanguage
                var titles = tab.translationMenuItems().map(\.title)
                if target.languageCode != "de" {
                    #expect(titles.first == "Translate to \(PageLanguage.name(of: target))")
                }
                #expect(titles.last == "Translate Page…")

                runtime.translation = .translated(PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: target
                ))
                titles = tab.translationMenuItems().map(\.title)
                #expect(titles == ["Show Original", "Translate Page…"])

                let panelItem = try #require(tab.translationMenuItems().last)
                try NSApp.sendAction(#require(panelItem.action), to: panelItem.target, from: panelItem)
                #expect(runtime.showsTranslationPanel)

                runtime.pageLanguage = nil
                #expect(tab.translationMenuItems().isEmpty)
            }
        }

        /// Apple's Translation with German already on the Mac: the page is
        /// translated, without any prompt.
        @Test func germanOnTheMacIsTranslated() async throws {
            let pair = (Locale.Language(identifier: "de"), Locale.Language(identifier: "fr"))
            guard #available(macOS 26.0, *),
                  await LanguageAvailability().status(from: pair.0, to: pair.1) == .installed
            else { return }
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                tab.translatePage(to: pair.1)
                try await waitUntilSettled(runtime, seconds: 30)
                #expect(runtime.translation == .translated(PageTranslationPair(source: pair.0, target: pair.1)))
                #expect(runtime.translationRequest == nil)
                let translated = try #require(await text(tab, "a"))
                #expect(translated != "Guten Morgen")
                let session = try #require(runtime.translationSession?.session)

                // Again after the original: same session, from the page's memory.
                #expect(runtime.translationMemory?.translations.isEmpty == false)
                tab.showOriginalPage()
                #expect(await text(tab, "a") == "Guten Morgen")
                let start = Date()
                tab.translatePage(to: pair.1)
                try await waitUntilSettled(runtime, seconds: 30)
                #expect(Date().timeIntervalSince(start) < 3)
                #expect(await text(tab, "a") == translated)
                #expect(runtime.translationSession?.session === session)
                tab.showOriginalPage()
            }
        }

        /// The page's memory: translated again from it, never asked twice;
        /// a new document starts with none.
        @Test func aPageIsTranslatedOnce() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                let pair = PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: Locale.Language(identifier: "fr")
                )
                let counting = UpperCase()
                for _ in 0 ..< 2 {
                    let runID = UUID()
                    runtime.translationRunID = runID
                    let translator = MemorizingTranslator(base: counting, memory: runtime.translationMemory(for: pair))
                    await tab.runTranslation(pair, translator: translator, needsDownload: false, runID: runID)
                    #expect(runtime.translation == .translated(pair))
                    #expect(await text(tab, "a") == "GUTEN MORGEN")
                    tab.showOriginalPage()
                }
                #expect(counting.translatedPieces == 2)

                runtime.resetTranslation()
                #expect(runtime.translationMemory == nil)
            }
        }

        /// A language not on the Mac: the translation asks the page's view
        /// for a session, whose prompt downloads it (shown by macOS, not here).
        @Test func aLanguageNotOnTheMacAsksForTheDownload() async throws {
            let languages = await LanguageAvailability().supportedLanguages
            let target = Locale.Language(identifier: "fr")
            var missing: Locale.Language?
            for language in languages
                where await LanguageAvailability().status(from: language, to: target) == .supported
            {
                missing = language
                break
            }
            guard let missing else { return }
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                runtime.pageLanguage = missing
                tab.translatePage(to: target)
                for _ in 0 ..< 100 where runtime.translationRequest == nil {
                    try await Task.sleep(for: .milliseconds(50))
                }
                let request = try #require(runtime.translationRequest)
                #expect(request.needsDownload)
                #expect(request.pair == PageTranslationPair(source: missing, target: target))
                tab.showOriginalPage()
                #expect(runtime.translationRequest == nil)
                #expect(runtime.translation == .original)
            }
        }

        /// A run replaced by a later one changes nothing anymore.
        @Test func anOlderRunLeavesTheStateAlone() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                let pair = PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: Locale.Language(identifier: "fr")
                )
                runtime.translationRunID = UUID()
                runtime.translation = .preparing(pair)
                await tab.runTranslation(pair, translator: UpperCase(), needsDownload: false, runID: UUID())
                #expect(runtime.translation == .preparing(pair))
                #expect(await text(tab, "a") == "Guten Morgen")
            }
        }

        /// Stopped while at work without the user asking (the page's view
        /// hidden): said, never left turning.
        @Test func aRunStoppedAtWorkIsTold() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                let pair = PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: Locale.Language(identifier: "fr")
                )
                let translator = UpperCase()
                translator.waits = true
                let runID = UUID()
                runtime.translationRunID = runID
                let run = Task { @MainActor in
                    await tab.runTranslation(pair, translator: translator, needsDownload: false, runID: runID)
                }
                for _ in 0 ..< 100 where runtime.translation != .translating(pair, done: 0, total: 2) {
                    try await Task.sleep(for: .milliseconds(20))
                }
                run.cancel()
                await run.value
                translator.letGo()
                guard case let .failed(_, message, _) = runtime.translation else {
                    Issue.record("Expected a message, got \(runtime.translation)")
                    return
                }
                #expect(message.contains("stopped before it finished"))
                #expect(runtime.showsTranslationPanel)
            }
        }

        /// Each request for the view's session starts its task again, even
        /// for the same languages.
        @Test func eachSessionRequestDiffers() async throws {
            try await TabManagerTestWindow.run { window in
                let runtime = try #require(try await window.openLoaded("page").runtime)
                let pair = PageTranslationPair(
                    source: Locale.Language(identifier: "de"),
                    target: Locale.Language(identifier: "fr")
                )
                runtime.requestTranslationSession(id: UUID(), pair: pair, needsDownload: true)
                let first = try #require(runtime.translationRequest?.configuration)
                runtime.requestTranslationSession(id: UUID(), pair: pair, needsDownload: true)
                #expect(runtime.translationRequest?.configuration != first)
                runtime.stopTranslation()
            }
        }

        /// "Always translate German" translates German pages at once, but not
        /// on a site the user never wants translated.
        @Test(arguments: [false, true])
        func alwaysTranslatedUnlessNeverOnThisSite(neverOnSite: Bool) async throws {
            let settings = PageTranslationSettings.standard
            let german = Locale.Language(identifier: "de")
            guard PageLanguage.offersTranslation(of: german, to: PageLanguage.userLanguages) else { return }
            settings.setAlwaysTranslates(german, true)
            settings.setNeverTranslates(host: "example.com", neverOnSite)
            defer {
                settings.setAlwaysTranslates(german, false)
                settings.setNeverTranslates(host: "example.com", false)
            }
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                let runtime = try #require(tab.runtime)
                runtime.pageLanguage = nil
                tab.url = try #require(URL(string: "https://example.com/"))
                tab.checkPageLanguage()
                for _ in 0 ..< 100 where runtime.pageLanguage == nil {
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(runtime.pageLanguage?.languageCode == "de")
                #expect((runtime.translation == .original) == neverOnSite)
                tab.showOriginalPage()
            }
        }

        /// The same language as the page: said, never a translation.
        @Test func sameLanguageIsTold() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await tab(showing: Self.german, in: window)
                tab.translatePage(to: Locale.Language(identifier: "de-AT"))
                guard case let .failed(_, message, _) = tab.runtime?.translation else {
                    Issue.record("Expected a message")
                    return
                }
                #expect(message.contains("already"))
            }
        }
    }
}

private final class UpperCase: PageTextTranslating, @unchecked Sendable {
    /// Translations wait for `release` (a run stopped while at work).
    var waits = false
    /// Pieces asked so far.
    private(set) var translatedPieces = 0
    private var release: CheckedContinuation<Void, Never>?

    func prepare() async throws {}

    func cancel() {}

    func letGo() {
        release?.resume()
        release = nil
    }

    func translate(_ pieces: [PageTextPiece]) async throws -> [String: String] {
        if waits { await withCheckedContinuation { release = $0 } }
        translatedPieces += pieces.count
        return Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0.text.uppercased()) })
    }
}
