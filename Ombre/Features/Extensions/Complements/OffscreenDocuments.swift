import Foundation
@preconcurrency import WebKit

/// `chrome.offscreen`: one hidden page of the extension's own, for a
/// service worker that needs a document (the clipboard, audio, a DOM
/// parser…), as in Chrome. Never in a window; closed with the extension.
@available(macOS 15.4, *)
@MainActor
final class OffscreenDocuments {
    private final class Document: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let url: URL
        private var loaded: CheckedContinuation<Void, Error>?

        init(webView: WKWebView, url: URL) {
            self.webView = webView
            self.url = url
            super.init()
            webView.navigationDelegate = self
        }

        func load() async throws {
            try await withCheckedThrowingContinuation { continuation in
                loaded = continuation
                webView.load(URLRequest(url: url))
            }
        }

        /// Closed while it loads: `createDocument` answers, once.
        func cancel() {
            finish(CancellationError())
        }

        private func finish(_ error: Error?) {
            guard let loaded else { return }
            self.loaded = nil
            if let error { loaded.resume(throwing: error) } else { loaded.resume() }
        }

        // swiftlint:disable:next implicitly_unwrapped_optional
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(nil)
        }

        // swiftlint:disable:next implicitly_unwrapped_optional
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(error)
        }
    }

    /// By extension id: Chrome allows one.
    private var documents: [String: Document] = [:]

    func hasDocument(for id: String) -> Bool {
        documents[id] != nil
    }

    func handle(_ method: String, _ details: [String: Any], context: WKWebExtensionContext) async throws -> Any? {
        let id = context.uniqueIdentifier
        switch method {
        case "createDocument":
            guard documents[id] == nil else {
                throw ExtensionComplementFailure
                    .invalid("Only a single offscreen document may be created.") // not shown
            }
            guard let path = details["url"] as? String, let url = Self.url(path, in: context.baseURL) else {
                throw ExtensionComplementFailure.invalid("Invalid offscreen document URL.") // not shown
            }
            guard let reasons = details["reasons"] as? [Any], !reasons.isEmpty else {
                throw ExtensionComplementFailure.invalid("A reason must be given.") // not shown
            }
            guard let configuration = context.webViewConfiguration else {
                throw ExtensionComplementFailure.invalid("The extension isn't loaded.") // not shown
            }
            let document = Document(webView: WKWebView(frame: .zero, configuration: configuration), url: url)
            documents[id] = document
            do {
                try await document.load()
            } catch {
                if documents[id] === document { documents[id] = nil }
                throw ExtensionComplementFailure.invalid("The offscreen document couldn't load.") // not shown
            }
            return nil
        case "closeDocument":
            guard documents[id] != nil else {
                throw ExtensionComplementFailure.invalid("No current offscreen document.") // not shown
            }
            close(for: id)
            return nil
        case "hasDocument":
            return documents[id] != nil
        case "contexts":
            // `runtime.getContexts`, for its offscreen document only.
            let types = (details["contextTypes"] as? [Any])?.compactMap { $0 as? String }
            let offscreenType = "OFFSCREEN_DOCUMENT" // not shown
            guard let document = documents[id], types == nil || types?.contains(offscreenType) == true else {
                return [Any]()
            }
            return [[
                "contextType": offscreenType, "documentUrl": document.url.absoluteString, // not shown
                "documentOrigin": context.baseURL.absoluteString.trimmingCharacters(in: ["/"]),
                "incognito": false, "frameId": -1, "tabId": -1, "windowId": -1, "contextId": "offscreen-\(id)"
            ]]
        default:
            throw ExtensionComplementFailure.unknownCall("offscreen.\(method)")
        }
    }

    /// A page of the extension: a path in it, never another site or extension.
    static func url(_ path: String, in base: URL) -> URL? {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host
        else { return nil }
        return url
    }

    func close(for id: String) {
        guard let document = documents.removeValue(forKey: id) else { return }
        document.cancel()
        document.webView.stopLoading()
        document.webView.navigationDelegate = nil
    }
}
