import Foundation

/// Decides whether a message posted by one of our injected scripts can be trusted.
///
/// Message handlers are reachable from every frame, even though our scripts only
/// run in the main frame: a third-party iframe (an ad, say) could otherwise post
/// fake password submissions, favicons or hovered links for the page. A late
/// message from the previous page during a navigation is dropped too.
enum ScriptMessagePolicy {
    /// - Parameters:
    ///   - isMainFrame: whether the message comes from the page's main frame.
    ///   - frameScheme: the sending frame's security origin scheme (`WKSecurityOrigin.protocol`).
    ///   - frameHost: the sending frame's security origin host.
    ///   - framePort: the sending frame's security origin port; WebKit reports 0 for the default port.
    ///   - pageURL: the page's current URL (`WKWebView.url`).
    nonisolated static func accepts(
        isMainFrame: Bool,
        frameScheme: String,
        frameHost: String,
        framePort: Int,
        pageURL: URL?
    ) -> Bool {
        guard isMainFrame,
              let pageURL,
              let pageScheme = pageURL.scheme?.lowercased(),
              let pageHost = pageURL.host(percentEncoded: false)?.lowercased()
        else {
            return false
        }

        let scheme = frameScheme.lowercased()
        guard scheme == pageScheme, frameHost.lowercased() == pageHost else {
            return false
        }

        return effectivePort(framePort, scheme: scheme) == effectivePort(pageURL.port, scheme: scheme)
    }

    /// 0 (WebKit), no port and the scheme's default port all mean the same port.
    private nonisolated static func effectivePort(_ port: Int?, scheme: String) -> Int? {
        guard let port, port > 0 else { return defaultPort(for: scheme) }
        return port
    }

    private nonisolated static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http": 80
        case "https": 443
        default: nil
        }
    }
}
