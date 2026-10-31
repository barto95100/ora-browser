import Foundation
@testable import Ora
import Testing

struct PasswordOriginMatchTests {
    private func matches(origin: String?, host: String = "bank.example", page: String) throws -> Bool {
        let url = try #require(URL(string: page))
        return PasswordManagerService.entry(origin: origin, host: host, matches: url)
    }

    @Test func sameOriginMatches() throws {
        #expect(try matches(origin: "https://bank.example", page: "https://bank.example/login"))
    }

    @Test func redirectToAnotherSiteDoesNotMatch() throws {
        #expect(try !matches(origin: "https://bank.example", page: "https://evil.example/login"))
    }

    @Test func plainHTTPDoesNotMatchHTTPSEntry() throws {
        #expect(try !matches(origin: "https://bank.example", page: "http://bank.example/login"))
    }

    @Test func otherPortDoesNotMatch() throws {
        #expect(try !matches(origin: "https://bank.example", page: "https://bank.example:8443/login"))
    }

    @Test func legacyEntryMatchesWithOrWithoutWWW() throws {
        #expect(try matches(origin: nil, host: "www.bank.example", page: "https://bank.example/"))
        #expect(try matches(origin: nil, host: "bank.example", page: "https://www.bank.example/"))
    }

    @Test func legacyEntryDoesNotMatchOnCustomPortOrHTTP() throws {
        #expect(try !matches(origin: nil, page: "https://bank.example:8443/"))
        #expect(try !matches(origin: nil, page: "http://bank.example/"))
    }

    @Test func legacyEntryDoesNotMatchAnotherHost() throws {
        #expect(try !matches(origin: nil, page: "https://evil.example/"))
    }
}
