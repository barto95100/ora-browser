import Foundation
@testable import Ombre
import Testing

/// The log keeps the site only, and nothing of a private window.
struct PageLogTests {
    @Test(arguments: [
        ("http://10.150.150.84:8078/admin/login?token=secret", "10.150.150.84:8078"),
        ("https://user:pass@www.example.com/path#frag", "www.example.com"),
        ("about:blank", "about:"),
        ("file:///Users/someone/Documents/page.html", "file:")
    ])
    func theSiteOnly(address: String, logged: String) throws {
        let url = try #require(URL(string: address))
        #expect(PageLog.site(url, isPrivate: false) == logged)
    }

    @Test func nothingOfAPrivateWindow() throws {
        let url = try #require(URL(string: "https://www.example.com/"))
        #expect(PageLog.site(url, isPrivate: true) == "private")
        #expect(PageLog.site(nil, isPrivate: false) == "none")
    }

    @Test func errorsAsDomainAndCode() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        #expect(PageLog.describe(error) == "NSURLErrorDomain -1202")
    }
}
