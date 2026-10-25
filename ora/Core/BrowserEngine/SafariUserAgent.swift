import AppKit
import Foundation

/// The part of the user agent Ora hands to WebKit.
///
/// WebKit appends `WKWebViewConfiguration.applicationNameForUserAgent` to its
/// own "Mozilla/5.0 (Macintosh; …) AppleWebKit/605.1.15 (KHTML, like Gecko)"
/// prefix, so it must only hold Safari's suffix; a full user agent there ends
/// up duplicated. Using the installed Safari's version keeps Ora's user agent
/// identical to Safari's — the crowd it should blend into — across updates.
enum SafariUserAgent {
    static let safariToken = "Safari/605.1.15"

    /// Used when the installed Safari's version cannot be read.
    static let fallbackVersion = "26.0"

    /// Computed once: Safari's version only changes with a macOS update.
    static let current = applicationName(safariVersion: installedSafariVersion)

    static func applicationName(safariVersion: String?) -> String {
        let version = safariVersion.flatMap(sanitizedVersion) ?? fallbackVersion
        return "Version/\(version) \(safariToken)"
    }

    static var installedSafariVersion: String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            return nil
        }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Accepts plain dotted versions only ("26.6.2"), so nothing unexpected
    /// can ever end up in the user agent.
    static func sanitizedVersion(_ version: String) -> String? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 4).contains(parts.count),
              parts.allSatisfy({ part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return version
    }
}
