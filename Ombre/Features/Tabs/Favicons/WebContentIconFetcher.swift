import Foundation
import os.log
import WebKit

/// Downloads the icons of `http` sites through WebKit. App Transport Security
/// refuses plain `http` to the app's own requests (`URLSession`, error
/// -1022) and allows it only to web content (`NSAllowsArbitraryLoadsInWebContent`):
/// the icon is fetched by an empty page of the icon's own origin, made
/// without any request, in a hidden web view.
///
/// Same rules as `FaviconStore`'s requests: no cookies (a data store of its
/// own, in memory, and `credentials: "omit"`), Safari's user agent, no cache;
/// nothing on the disk. The web view goes after a short idle time.
@MainActor
final class WebContentIconFetcher: NSObject, WKNavigationDelegate {
    static let shared = WebContentIconFetcher()

    private static let logger = Logger(category: "Favicons")
    /// How long the hidden web view (and its web content process) stays
    /// after the last icon.
    static let idleTime: Duration = .seconds(30)

    /// What `FaviconStore` calls for an `http` icon.
    static func icon(from iconURL: URL) async -> Data? {
        await shared.data(from: iconURL)
    }

    private var webView: WKWebView?
    private var loading: CheckedContinuation<Bool, Never>?
    /// One icon at a time: each changes the page's origin.
    private var queue: Task<Void, Never>?
    private var release: Task<Void, Never>?

    /// The icon's data, or nil when it can't be had (or is larger than
    /// `maximumSize`).
    /// `origin`: the hidden page's address, the icon's origin unless a test
    /// gives another.
    func data(
        from iconURL: URL,
        origin: URL? = nil,
        maximumSize: Int = FaviconStore.maximumSize
    ) async -> Data? {
        let previous = queue
        let fetch = Task { () -> Data? in
            await previous?.value
            return await self.fetch(iconURL, origin: origin ?? Self.origin(of: iconURL), maximumSize: maximumSize)
        }
        queue = Task { _ = await fetch.value }
        return await fetch.value
    }

    private func fetch(_ iconURL: URL, origin: URL?, maximumSize: Int) async -> Data? {
        release?.cancel()
        defer { scheduleRelease() }
        guard let origin else { return nil }
        let webView = webView ?? makeWebView()
        let loaded = await withCheckedContinuation { continuation in
            loading = continuation
            // Nothing is requested: the empty page takes the icon's origin, so
            // the icon is a same-origin request (no CORS).
            webView.loadHTMLString("<!doctype html>", baseURL: origin) // not shown
        }
        guard loaded else { return nil }
        do {
            let value = try await webView.callAsyncJavaScript(
                Self.script,
                arguments: ["address": iconURL.absoluteString, "limit": maximumSize],
                contentWorld: .defaultClient
            )
            guard let encoded = value as? String else { return nil }
            return Data(base64Encoded: encoded)
        } catch {
            Self.logger.notice("http icon not fetched: \(error.localizedDescription, privacy: .public)") // not shown
            return nil
        }
    }

    /// The scheme, host and port of `url`: the hidden page's address.
    static func origin(of url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/"
        return components.url
    }

    /// Returns the icon as Base64, or null. Aborted after 15 s, like
    /// `FaviconStore`'s requests.
    static let script = """
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
        const response = await fetch(address, {
            credentials: "omit", cache: "no-store", referrerPolicy: "no-referrer", signal: controller.signal
        });
        if (!response.ok) { return null; }
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.length === 0 || bytes.length > limit) { return null; }
        let binary = "";
        for (let start = 0; start < bytes.length; start += 0x8000) {
            binary += String.fromCharCode.apply(null, bytes.subarray(start, start + 0x8000));
        }
        return btoa(binary);
    } finally {
        clearTimeout(timer);
    }
    """ // not shown

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // In memory, and its own: none of the spaces' cookies.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = FaviconStore.userAgent
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func scheduleRelease() {
        release?.cancel()
        release = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTime)
            guard !Task.isCancelled else { return }
            self?.webView = nil
        }
    }

    private func finishLoading(_ loaded: Bool) {
        loading?.resume(returning: loaded)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishLoading(false)
        if webView === self.webView { self.webView = nil }
    }
}
