import Foundation

/// "HTTPS first", like Safari and Chrome: an `http://` address is tried over
/// HTTPS, and falls back to HTTP without any error when the site does not
/// answer over HTTPS or sends the page back to HTTP. Local network addresses
/// (localhost, IPs, `.local`, `.lan`…) and explicit ports are left alone.
/// One per page: a site that only works over HTTP is remembered for its tab.
struct HTTPSUpgradePolicy {
    /// Hosts that did not work over HTTPS in this page: left on HTTP.
    private(set) var hostsLeftOnHTTP: Set<String> = []
    /// The HTTP address being tried over HTTPS, until that load commits.
    private(set) var pendingFallback: URL?

    private static let localSuffixes = [
        ".local", ".lan", ".home", ".home.arpa", ".internal", ".localhost", ".localdomain",
        ".test", ".example", ".invalid"
    ]

    /// The HTTPS address to load instead of a main-frame HTTP page, or nil to
    /// load the page as it is.
    mutating func upgrade(_ url: URL, httpMethod: String?) -> URL? {
        guard url.scheme?.lowercased() == "http",
              (httpMethod ?? "GET").uppercased() == "GET",
              url.port == nil,
              let host = url.host?.lowercased(),
              Self.isPublic(host)
        else { return nil }

        // The HTTPS address sent the page back to HTTP: the site wants HTTP.
        if pendingFallback?.host?.lowercased() == host {
            leaveOnHTTP(host)
            return nil
        }
        guard !hostsLeftOnHTTP.contains(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "https"
        guard let upgraded = components.url else { return nil }
        pendingFallback = url
        return upgraded
    }

    /// After a load failed: the HTTP address to load instead, when the failure
    /// is an HTTPS attempt the site could not answer.
    mutating func fallback(afterFailing failingURL: URL?, error: Error) -> URL? {
        guard let pending = pendingFallback,
              let host = pending.host?.lowercased(),
              failingURL?.scheme?.lowercased() == "https",
              failingURL?.host?.lowercased() == host,
              Self.isHTTPSFailure(error)
        else { return nil }
        leaveOnHTTP(host)
        return pending
    }

    /// The page started to show: the HTTPS attempt worked.
    mutating func navigationCommitted() {
        pendingFallback = nil
    }

    private mutating func leaveOnHTTP(_ host: String) {
        hostsLeftOnHTTP.insert(host)
        pendingFallback = nil
    }

    /// Whether the host is on the internet, not on the local network.
    static func isPublic(_ host: String) -> Bool {
        guard host.contains("."), !host.contains(":") else { return false } // single label, IPv6
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false } // IPv4
        return !localSuffixes.contains { host.hasSuffix($0) }
    }

    /// Failures meaning the site does not serve this page over HTTPS.
    static func isHTTPSFailure(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut
        ].contains(error.code)
    }
}
