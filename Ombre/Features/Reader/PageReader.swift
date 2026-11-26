import AppKit
import Observation
import WebKit

/// Reader mode of one page (a tab's, Peek's or Little Ombre's): whether
/// the page holds an article, offered by the address bar like Safari's,
/// and the article shown over the page (⇧⌘R).
///
/// Asked once per page loaded, when it has finished loading: a short look
/// at its paragraphs, no timer and nothing more until the next page.
@MainActor
@Observable
final class PageReader {
    /// The page looks like an article: the address bar offers reader mode.
    private(set) var isAvailable = false
    /// Shown over the page while set.
    private(set) var article: ReaderArticle?
    /// The article is being taken from the page.
    private(set) var isOpening = false

    var isShown: Bool {
        article != nil
    }

    /// The page that was there when a look started: a later one answers for itself.
    @ObservationIgnored private var generation = 0

    static func canRead(_ url: URL?) -> Bool {
        url?.scheme == "https" || url?.scheme == "http"
    }

    /// Another page (not a change within the same one): reader mode closes,
    /// the keyboard back to the page.
    func pageCommitted(_ page: BrowserPage) {
        generation += 1
        isAvailable = false
        isOpening = false
        close(page)
    }

    func pageFinished(_ page: BrowserPage) {
        guard !page.isExtensionPage, Self.canRead(page.currentURL) else { return }
        let current = generation
        call("return reader.isReadable();", in: page) { [weak self] value in // not shown
            guard let self, generation == current else { return }
            isAvailable = value as? Bool ?? false
        }
    }

    func toggle(_ page: BrowserPage) {
        if isShown {
            close(page)
        } else {
            open(page)
        }
    }

    /// Takes the article from the page; a page without one: a beep, as Safari.
    func open(_ page: BrowserPage) {
        guard !isShown, !isOpening, !page.isExtensionPage, Self.canRead(page.currentURL),
              let address = page.currentURL
        else { return NSSound.beep() }
        isOpening = true
        let current = generation
        call("return reader.extract();", in: page) { [weak self] value in // not shown
            guard let self, generation == current else { return }
            isOpening = false
            guard let article = ReaderArticle(value, pageURL: address) else { return NSSound.beep() }
            isAvailable = true
            self.article = article
        }
    }

    /// Closed; the keyboard goes back to the page if the article had it
    /// (not taken from the address bar, say).
    func close(_ page: BrowserPage) {
        guard isShown else { return }
        article = nil
        guard let window = page.webView.window else { return }
        var responder = window.firstResponder as? NSView
        while let view = responder, !(view is ReaderPageWebView) {
            responder = view.superview
        }
        if responder != nil || window.firstResponder === window {
            window.makeFirstResponder(page.webView)
        }
    }

    private func call(_ body: String, in page: BrowserPage, completion: @escaping @MainActor (Any?) -> Void) {
        page.webView.callAsyncJavaScript(
            ReaderScript.script(body),
            arguments: [:],
            in: nil,
            in: ReaderScript.world
        ) { result in
            completion(try? result.get())
        }
    }
}
