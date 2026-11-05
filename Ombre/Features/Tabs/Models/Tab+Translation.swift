import Foundation
import Translation

/// Page translation, like Safari: offered when the page isn't in the Mac's
/// language, done on the Mac (Apple's Translation, nothing sent away), with
/// the original a click away.
@MainActor
extension Tab {
    /// A page loaded: whether to offer translating it.
    func checkPageLanguage() {
        guard let runtime, let page = browserPage else { return }
        // The page this check is for: a later page must not get its offer.
        let address = url
        page.evaluateJavaScript("window.__translator ? window.__translator.info() : null") { [weak self] value, _ in
            guard let self, let json = value as? String,
                  let info = try? JSONDecoder().decode(PageInfo.self, from: Data(json.utf8)),
                  let source = PageLanguage.detect(declared: info.lang, sample: info.sample),
                  PageLanguage.offersTranslation(of: source, to: PageLanguage.userLanguages)
            else { return }
            Task { @MainActor in
                let status = await LanguageAvailability().status(from: source, to: PageLanguage.userLanguage)
                guard status != .unsupported, runtime.page === page, self.url == address,
                      runtime.translation == .unavailable
                else { return }
                // Back from the back/forward cache, still translated.
                runtime.translation = info.translated ? .translated(from: source) : .offered(from: source)
            }
        }
    }

    /// The address bar's button: translate, stop translating, or show the
    /// original again.
    func toggleTranslation() {
        guard let runtime else { return }
        switch runtime.translation {
        case let .offered(source):
            runtime.translation = .translating(from: source)
        case let .translating(source):
            // Its task is cancelled with it (see `PageTranslationHost`); what
            // was already shown goes back to the original.
            browserPage?.evaluateJavaScript("window.__translator && window.__translator.restore()")
            runtime.translation = .offered(from: source)
        case let .translated(source):
            browserPage?.evaluateJavaScript("window.__translator && window.__translator.restore()")
            runtime.translation = .offered(from: source)
        case .unavailable:
            break
        }
    }

    /// Translates the page's text with `session` (see `PageTranslationHost`),
    /// showing it as it comes, a hundred pieces at a time.
    func translatePage(with session: TranslationSession) async {
        guard let runtime, case let .translating(source) = runtime.translation, let page = browserPage else { return }
        let texts = await withCheckedContinuation { continuation in
            page.evaluateJavaScript("window.__translator ? window.__translator.collect() : '[]'") { value, _ in
                let json = value as? String ?? "[]"
                continuation.resume(returning: (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? [])
            }
        }
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        var pending: [String: String] = [:]
        var didShow = false
        func show() {
            guard !pending.isEmpty, runtime.page === page,
                  let json = try? JSONEncoder().encode(pending), let object = String(data: json, encoding: .utf8),
                  let argument = try? JSONEncoder().encode(object), let literal = String(
                      data: argument,
                      encoding: .utf8
                  )
            else { return }
            page.evaluateJavaScript("window.__translator && window.__translator.apply(\(literal))")
            pending = [:]
            didShow = true
        }
        do {
            for try await response in session.translate(batch: requests) {
                guard case .translating = runtime.translation else { return }
                if let index = response.clientIdentifier { pending[index] = response.targetText }
                if pending.count >= 100 { show() }
            }
            show()
            if case .translating = runtime.translation { runtime.translation = .translated(from: source) }
        } catch {
            // Stopped by the user: already put back (`toggleTranslation`).
            guard case .translating = runtime.translation else { return }
            // Failed (the language not downloaded…): what came stays shown,
            // with the original a click away.
            show()
            runtime.translation = didShow ? .translated(from: source) : .offered(from: source)
        }
    }
}

private struct PageInfo: Decodable {
    let lang: String
    let sample: String
    let translated: Bool
}
