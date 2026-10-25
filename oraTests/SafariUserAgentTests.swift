@testable import Ora
import Testing

struct SafariUserAgentTests {
    @Test func applicationNameIsOnlySafarisSuffix() {
        let name = SafariUserAgent.applicationName(safariVersion: "26.6.2")

        #expect(name == "Version/26.6.2 Safari/605.1.15")
        // WebKit adds the "Mozilla/5.0 … AppleWebKit …" prefix itself.
        #expect(!name.contains("Mozilla"))
        #expect(!name.contains("AppleWebKit"))
    }

    @Test func unreadableOrUnexpectedVersionsFallBack() {
        let fallback = "Version/\(SafariUserAgent.fallbackVersion) Safari/605.1.15"

        #expect(SafariUserAgent.applicationName(safariVersion: nil) == fallback)
        #expect(SafariUserAgent.applicationName(safariVersion: "") == fallback)
        #expect(SafariUserAgent.applicationName(safariVersion: "26.6 beta") == fallback)
        #expect(SafariUserAgent.applicationName(safariVersion: "26..1") == fallback)
    }

    @Test func currentUserAgentIsWellFormed() {
        #expect(SafariUserAgent.current.hasPrefix("Version/"))
        #expect(SafariUserAgent.current.hasSuffix(" Safari/605.1.15"))
    }
}
