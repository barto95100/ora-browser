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

    /// What `FaviconStore` calls for an `http` icon, or an `https` one
    /// whose certificate the user accepted (`trusting`).
    static func icon(from iconURL: URL, trusting accepted: AcceptedCertificate?) async -> Data? {
        await shared.data(from: iconURL, trusting: accepted)
    }

    /// The certificate trusted for the icon being fetched (one at a time):
    /// any other untrusted one is refused, as macOS would.
    private var accepted: AcceptedCertificate?

    /// How long an icon may take, its page included: WebKit may suspend
    /// a hidden page's timers, so the script's own limit is not enough.
    private let timeout: Duration

    init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
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
        trusting accepted: AcceptedCertificate? = nil,
        maximumSize: Int = FaviconStore.maximumSize
    ) async -> Data? {
        let previous = queue
        let fetch = Task { () -> Data? in
            await previous?.value
            self.accepted = accepted
            defer { self.accepted = nil }
            return await self.fetch(iconURL, origin: origin ?? Self.origin(of: iconURL), maximumSize: maximumSize)
        }
        queue = Task { _ = await fetch.value }
        return await fetch.value
    }

    /// Gives up after `timeout`: the web view goes (with what it was
    /// doing), and the next icons don't wait behind this one.
    private func fetch(_ iconURL: URL, origin: URL?, maximumSize: Int) async -> Data? {
        release?.cancel()
        defer { scheduleRelease() }
        guard let origin else { return nil }
        let answer = Answer()
        var limit: Task<Void, Never>?
        let data = await withCheckedContinuation { continuation in
            answer.continuation = continuation
            Task {
                await answer.give(self.load(iconURL, origin: origin, maximumSize: maximumSize))
            }
            limit = Task { [timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, answer.isWaiting else { return }
                Self.logger.notice("http icon not fetched: too long") // not shown
                self.abandon()
                answer.give(nil)
            }
        }
        limit?.cancel()
        return data
    }

    private func abandon() {
        finishLoading(false)
        webView?.stopLoading()
        webView = nil
    }

    private func load(_ iconURL: URL, origin: URL, maximumSize: Int) async -> Data? {
        let webView = webView ?? makeWebView()
        // One load at a time (the queue): a load still waiting is given up.
        finishLoading(false)
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
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.percentEncodedHost?.isEmpty == false
        else { return nil }
        // The host as written (an IPv6 address keeps its brackets).
        components.user = nil
        components.password = nil
        components.path = "/"
        components.query = nil
        components.fragment = nil
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
        if (Number(response.headers.get("content-length")) > limit) { return null; }
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
        // Hidden, it would be suspended: the icon would never come.
        configuration.preferences.inactiveSchedulingPolicy = .none
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
        // Not from a web view given up (`abandon`).
        guard webView === self.webView else { return }
        finishLoading(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Not from a web view given up (`abandon`).
        guard webView === self.webView else { return }
        finishLoading(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Not from a web view given up (`abandon`).
        guard webView === self.webView else { return }
        finishLoading(false)
    }

    /// Trusts the server only when it presents the certificate the user
    /// accepted for this host; everything else as macOS decides.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if webView === self.webView, space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let accepted, let trust = space.serverTrust,
           accepted.trusts(host: space.host, digest: CertificateException.digest(of: trust))
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        finishLoading(false)
        self.webView = nil
    }
}

/// The one answer of a fetch: from its work or from its time limit, the
/// first to come.
@MainActor
private final class Answer {
    var continuation: CheckedContinuation<Data?, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func give(_ data: Data?) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
