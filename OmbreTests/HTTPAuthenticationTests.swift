import Foundation
@testable import Ombre
import Testing

/// Logins the server asks for (MOT-11).
struct HTTPAuthenticationTests {
    private func request(
        realm: String? = "Router",
        isSecure: Bool = true,
        failures: Int = 0
    ) -> HTTPAuthenticationRequest {
        HTTPAuthenticationRequest(
            host: "192.168.1.1", realm: realm, isSecure: isSecure, previousFailureCount: failures, proposedUser: nil
        )
    }

    @Test func asksForTheServersLoginsOnly() {
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodHTTPBasic, previousFailureCount: 0)
            == .ask)
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodHTTPDigest, previousFailureCount: 1)
            == .ask)
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodNTLM, previousFailureCount: 2) == .ask)
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodServerTrust, previousFailureCount: 0)
            == .defaultHandling)
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodClientCertificate, previousFailureCount: 0)
            == .defaultHandling)
    }

    /// A page can't make the sheet come back forever.
    @Test func givesUpAfterThreeRefusals() {
        #expect(HTTPAuthentication.decision(method: NSURLAuthenticationMethodHTTPBasic, previousFailureCount: 3)
            == .giveUp)
    }

    @Test func privateWindowsKeepNothing() {
        #expect(HTTPAuthentication.persistence(isPrivate: true) == .none)
        #expect(HTTPAuthentication.persistence(isPrivate: false) == .forSession)
    }

    @Test func sheetSaysWhoAsksAndWarnsWithoutEncryption() {
        #expect(HTTPAuthentication.title(for: request()) == "Log in to 192.168.1.1")
        #expect(HTTPAuthentication.message(for: request()) == "The site says: “Router”")
        let insecure = HTTPAuthentication.message(for: request(realm: nil, isSecure: false, failures: 1))
        #expect(insecure.contains("not accepted"))
        #expect(insecure.contains("unencrypted"))
        #expect(!insecure.contains("The site says"))
    }
}
