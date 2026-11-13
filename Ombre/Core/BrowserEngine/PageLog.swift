import Foundation
import os.log

/// What pages and tabs go through, in the app's log ("Pages"), kept by macOS
/// in Release too (notice level) for a problem report (`scripts/report.sh`).
/// The site only (host and port), never the rest of an address, and nothing
/// of a private window's sites.
enum PageLog {
    private static let logger = Logger(category: "Pages")

    /// The site to write for `url`: its host and port, the scheme alone when it
    /// has no host (`about:`, `file:`), "private" in a private window.
    static func site(_ url: URL?, isPrivate: Bool) -> String {
        if isPrivate { return "private" }
        guard let url else { return "none" }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            return (url.scheme ?? "?") + ":"
        }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// An error as "domain code", what the report needs to tell failures apart.
    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
