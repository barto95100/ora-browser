import Foundation
@testable import Ora
import Testing

struct ScriptMessagePolicyTests {
    private func accepts(
        isMainFrame: Bool = true,
        scheme: String = "https",
        host: String = "bank.example",
        port: Int = 0,
        page: String?
    ) -> Bool {
        ScriptMessagePolicy.accepts(
            isMainFrame: isMainFrame,
            frameScheme: scheme,
            frameHost: host,
            framePort: port,
            pageURL: page.flatMap(URL.init(string:))
        )
    }

    @Test func mainFrameOfSameOriginIsAccepted() {
        #expect(accepts(page: "https://bank.example/login?next=/"))
    }

    @Test func iframeIsRejectedEvenWithSameOrigin() {
        #expect(!accepts(isMainFrame: false, page: "https://bank.example/login"))
    }

    @Test func otherHostIsRejected() {
        #expect(!accepts(host: "ads.example", page: "https://bank.example/login"))
    }

    @Test func otherSchemeIsRejected() {
        #expect(!accepts(scheme: "http", page: "https://bank.example/login"))
    }

    @Test func otherPortIsRejected() {
        #expect(!accepts(port: 8443, page: "https://bank.example:9443/login"))
    }

    @Test func webKitDefaultPortMatchesURLWithoutPort() {
        #expect(accepts(port: 0, page: "https://bank.example/login"))
    }

    @Test func webKitDefaultPortDoesNotMatchCustomPort() {
        #expect(!accepts(port: 0, page: "https://bank.example:8443/login"))
    }

    @Test func explicitDefaultPortIsEquivalent() {
        #expect(accepts(port: 443, page: "https://bank.example/login"))
        #expect(accepts(port: 0, page: "https://bank.example:443/login"))
        #expect(accepts(scheme: "http", port: 0, page: "http://bank.example:80/"))
    }

    @Test func customPortMatchesSamePort() {
        #expect(accepts(scheme: "http", host: "localhost", port: 8080, page: "http://localhost:8080/"))
    }

    @Test func hostAndSchemeCaseIsIgnored() {
        #expect(accepts(scheme: "HTTPS", host: "Bank.Example", page: "https://bank.example/"))
    }

    @Test func missingPageURLIsRejected() {
        #expect(!accepts(page: nil))
    }
}
