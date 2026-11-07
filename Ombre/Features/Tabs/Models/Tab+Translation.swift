import AppKit
import os
import Translation

private let logger = Logger(category: "Translation")

/// Page translation, like Safari and Zen: offered when the page isn't in the
/// Mac's language, into the language the user picks; done on the Mac by
/// Apple's Translation (nothing sent away), the visible text first; never
/// waiting without end (each step has a time limit and tells what failed);
/// the original a click away.
@MainActor
extension Tab {
    private var translationSettings: PageTranslationSettings {
        .standard
    }

    /// The address bar shows its translate button: the page is in another
    /// language than the Mac's (unless the user never wants it for this
    /// site), or it is translated, or the panel is open.
    var showsTranslationButton: Bool {
        guard let runtime else { return false }
        if runtime.translation != .original || runtime.showsTranslationPanel { return true }
        guard PageLanguage.offersTranslation(of: runtime.pageLanguage, to: PageLanguage.userLanguages) else {
            return false
        }
        return !translationSettings.neverTranslates(host: url.host)
    }

    /// A page loaded: reads its language, and translates it at once if the
    /// user always wants that language translated.
    func checkPageLanguage() {
        guard let runtime, let page = browserPage else { return }
        // The page this check is for: a later page must not get its language.
        let address = url
        page.evaluateJavaScript("window.__translator ? window.__translator.info() : null") { [weak self] value, _ in
            guard let self, let json = value as? String,
                  let info = try? JSONDecoder().decode(PageInfo.self, from: Data(json.utf8)),
                  let source = PageLanguage.detect(declared: info.lang, sample: info.sample)
            else { return }
            Task { @MainActor in
                guard await PageLanguage.canTranslate(source), runtime.page === page, self.url == address,
                      runtime.pageLanguage == nil
                else { return }
                runtime.pageLanguage = source
                let settings = self.translationSettings
                let target = settings.targetLanguage
                if info.translated {
                    // Back from the back/forward cache, still translated.
                    runtime.translation = .translated(PageTranslationPair(source: source, target: target))
                } else if PageLanguage.offersTranslation(of: source, to: PageLanguage.userLanguages),
                          settings.alwaysTranslates(source), !settings.neverTranslates(host: address.host)
                {
                    logger
                        .info("Translating at once: \(source.minimalIdentifier, privacy: .public) is always translated")
                    self.translatePage()
                }
            }
        }
    }

    /// Opens the translation panel over the page (the address bar's button,
    /// the View menu, the page's context menu).
    func showTranslationPanel() {
        runtime?.showsTranslationPanel = true
    }

    /// Translates the page into `target` (else the language the user picked).
    func translatePage(to target: Locale.Language? = nil) {
        guard let runtime, let source = runtime.pageLanguage, browserPage != nil else {
            logger.error("Can't translate: the page's language isn't known yet")
            return
        }
        let target = target ?? translationSettings.targetLanguage
        let pair = PageTranslationPair(source: source, target: target)
        // Another translation of the page first goes back to the original.
        if runtime.translation != .original { stopTranslation(restoring: true) }
        guard source.languageCode != target.languageCode else {
            runtime.translation = .failed(
                pair,
                message: "This page is already in \(PageLanguage.name(of: target)).",
                isPartial: false
            )
            return
        }
        let runID = UUID()
        runtime.translationRunID = runID
        runtime.translation = .translating(pair, done: 0, total: 0)
        let languages = "\(source.minimalIdentifier) → \(target.minimalIdentifier)"
        logger.info("Checking whether macOS has \(languages, privacy: .public)")
        let start = Date()
        Task { @MainActor in
            let status: LanguageAvailability.Status
            do {
                status = try await InstalledTranslationLanguages.status(of: pair)
            } catch {
                guard runtime.translationRunID == runID else { return }
                self.translationFailed(pair, "macOS didn't say whether it can translate this page. Try again.")
                return
            }
            guard runtime.translationRunID == runID else { return }
            let answer = "\(status) (\(String(format: "%.2f", Date().timeIntervalSince(start))) s)"
            logger.info("\(languages, privacy: .public): \(answer, privacy: .public)")
            self.startTranslation(pair, status: status, runID: runID)
        }
    }

    /// Translates with a session of its own, or asks the page's view for one
    /// (a language to download, or before macOS 26).
    private func startTranslation(_ pair: PageTranslationPair, status: LanguageAvailability.Status, runID: UUID) {
        guard let runtime else { return }
        let source = pair.source
        let target = pair.target
        switch status {
        case .installed:
            if #available(macOS 26.0, *) {
                // A session of its own: the translation goes on while
                // another tab is shown.
                let session = borrowSession(for: pair)
                let translator = MemorizingTranslator(
                    base: SessionTextTranslator(session: session),
                    memory: runtime.translationMemory(for: pair)
                )
                runtime.translationTask = Task { @MainActor in
                    await self.runTranslation(pair, translator: translator, needsDownload: false, runID: runID)
                    // Kept for the next translation once it worked; a run
                    // stopped or failed keeps it from anyone else.
                    if runtime.translation == .translated(pair), runtime.translationSession == nil {
                        runtime.translationSession = (pair, session)
                    }
                }
            } else {
                runtime.requestTranslationSession(id: runID, pair: pair, needsDownload: false)
            }
        case .supported:
            // macOS asks to download the language: its prompt comes with
            // the page's view (`PageTranslationHost`).
            runtime.requestTranslationSession(id: runID, pair: pair, needsDownload: true)
        case .unsupported:
            translationFailed(pair, PageTranslationRun.message(
                for: TranslationError.unsupportedLanguagePairing,
                pair: pair
            ))
        @unknown default:
            runtime.requestTranslationSession(id: runID, pair: pair, needsDownload: true)
        }
    }

    /// The tab's session for `pair`, kept from one translation to the next
    /// (a new one loads macOS's model again). Taken while a translation uses
    /// it: a run still stopping can only cancel its own session.
    @available(macOS 26.0, *)
    private func borrowSession(for pair: PageTranslationPair) -> TranslationSession {
        if let kept = runtime?.translationSession, kept.pair == pair {
            logger.info("Reusing the tab's translation session")
            runtime?.translationSession = nil
            return kept.session
        }
        runtime?.translationSession = nil
        return TranslationSession(installedSource: pair.source, target: pair.target)
    }

    /// Shows the page as it was written.
    func showOriginalPage() {
        guard let runtime else { return }
        logger.info("Showing the original page")
        stopTranslation(restoring: true)
        runtime.translation = .original
    }

    /// The translation `request` asked for, with the session of the page's
    /// view (see `PageTranslationHost`).
    func runTranslation(with session: TranslationSession, for request: PageTranslationRequest) async {
        guard let runtime else { return }
        await runTranslation(
            request.pair,
            translator: MemorizingTranslator(
                base: SessionTextTranslator(session: session),
                memory: runtime.translationMemory(for: request.pair)
            ),
            needsDownload: request.needsDownload,
            runID: request.id
        )
        // Done: a later request for the same languages starts the view's task again.
        if runtime.translationRequest == request { runtime.translationRequest = nil }
    }

    func runTranslation(
        _ pair: PageTranslationPair,
        translator: PageTextTranslating,
        needsDownload: Bool,
        runID: UUID,
        timeouts: PageTranslationTimeouts = .standard
    ) async {
        guard let runtime else { return }
        if let page = browserPage {
            await PageTranslationRun.run(
                pair,
                page: BrowserPageText(page: page),
                translator: translator,
                needsDownload: needsDownload,
                timeouts: timeouts
            ) { state in
                guard runtime.translationRunID == runID, runtime.page === page else { return false }
                // Languages macOS said it had, but failing: asked again next time.
                if case .failed = state { InstalledTranslationLanguages.forget(pair) }
                runtime.translation = state
                // Said where it can't be missed.
                if case .failed = state { runtime.showsTranslationPanel = true }
                return true
            }
        }
        // Still this page's translation, but stopped at work (the page's view
        // hidden, its page gone): said, never left turning.
        guard runtime.translationRunID == runID, runtime.translation.isBusy else { return }
        logger.info("Translation stopped before it finished")
        runtime.translationRunID = nil
        runtime.translation = .failed(
            pair,
            message: "The translation stopped before it finished (the page was hidden or reloaded). Try again.",
            isPartial: runtime.translation.showsTranslation
        )
        runtime.showsTranslationPanel = true
    }

    private func translationFailed(_ pair: PageTranslationPair, _ message: String) {
        guard let runtime else { return }
        logger.error("Translation not started: \(message, privacy: .public)")
        runtime.stopTranslation()
        runtime.translation = .failed(pair, message: message, isPartial: false)
        runtime.showsTranslationPanel = true
    }

    private func stopTranslation(restoring: Bool) {
        runtime?.stopTranslation()
        if restoring { browserPage?.evaluateJavaScript("window.__translator && window.__translator.restore()") }
    }
}

/// The page's context menu: translate it, or show the original again.
@MainActor
extension Tab {
    func translationMenuItems() -> [NSMenuItem] {
        guard let runtime, let source = runtime.pageLanguage else { return [] }
        let target = PageTranslationSettings.standard.targetLanguage
        var items: [NSMenuItem] = []
        if runtime.translation == .original {
            if source.languageCode != target.languageCode {
                items.append(TranslationMenuItem("Translate to \(PageLanguage.name(of: target))") { [weak self] in
                    self?.translatePage()
                })
            }
        } else {
            items.append(TranslationMenuItem("Show Original") { [weak self] in self?.showOriginalPage() })
        }
        items.append(TranslationMenuItem("Translate Page…") { [weak self] in self?.showTranslationPanel() })
        return items
    }
}

/// A context menu item running a closure.
private final class TranslationMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}

/// The page's text, through its translator script (in the app's world).
@MainActor
final class BrowserPageText: PageTextAccess {
    private let page: BrowserPage

    init(page: BrowserPage) {
        self.page = page
    }

    func collectText() async -> [String] {
        await withCheckedContinuation { continuation in
            page.evaluateJavaScript("window.__translator ? window.__translator.collect() : '[]'") { value, _ in
                let json = value as? String ?? "[]"
                continuation.resume(returning: (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? [])
            }
        }
    }

    func showTranslations(_ translations: [String: String]) {
        guard !translations.isEmpty,
              let json = try? JSONEncoder().encode(translations), let object = String(data: json, encoding: .utf8),
              let argument = try? JSONEncoder().encode(object), let literal = String(data: argument, encoding: .utf8)
        else { return }
        page.evaluateJavaScript("window.__translator && window.__translator.apply(\(literal))")
    }
}

private struct PageInfo: Decodable {
    let lang: String
    let sample: String
    let translated: Bool
}
