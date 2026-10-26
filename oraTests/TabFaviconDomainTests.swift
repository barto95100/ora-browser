import Foundation
@testable import Ora
import Testing

struct TabFaviconDomainTests {
    @Test func wwwIsIgnored() throws {
        let url = try #require(URL(string: "https://www.Example.com/page"))

        #expect(Tab.faviconDomain(of: url) == "example.com")
    }

    @Test func subdomainsAreDistinctSites() throws {
        let webcam = try #require(URL(string: "https://fr.webcamtests.com/"))
        let example = try #require(URL(string: "https://example.com/"))

        #expect(Tab.faviconDomain(of: webcam) == "fr.webcamtests.com")
        #expect(Tab.faviconDomain(of: webcam) != Tab.faviconDomain(of: example))
    }

    @Test func urlsWithoutHostHaveNoFavicon() {
        let file = URL(fileURLWithPath: "/tmp/page.html")

        #expect(Tab.faviconDomain(of: file) == nil)
    }
}
