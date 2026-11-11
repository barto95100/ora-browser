import Foundation
@preconcurrency import WebKit

/// Where an extension's own pages and files live: `safari-web-extension://`,
/// as in Safari, not WebKit's default `webkit-extension://`. Extensions made
/// for Safari check it: Bitwarden's menu under login fields accepts only the
/// `chrome-extension:`, `moz-extension:` and `safari-web-extension:` schemes,
/// and stays empty (a dark line under the field) on any other.
@available(macOS 15.4, *)
@MainActor
enum ExtensionBaseURL {
    static let scheme = "safari-web-extension"

    /// Before any extension loads: WebKit refuses a base URL whose scheme
    /// the match patterns don't know (an exception).
    static func registerScheme() {
        WKWebExtension.MatchPattern.registerCustomURLScheme(scheme)
    }

    /// The extension's base URL: its id as host, in lowercase like WebKit's
    /// own (`location.origin` is lowercased, and extensions compare it with
    /// their URLs), so the host is the one it had under `webkit-extension`.
    static func url(for id: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = id.lowercased()
        components.path = "/"
        return components.url
    }

    /// Only before the context loads (WebKit's rule).
    static func apply(to context: WKWebExtensionContext, id: String) {
        guard !context.isLoaded, let url = url(for: id) else { return }
        context.baseURL = url
    }
}
