import Foundation
@testable import Ombre
import Testing

@MainActor
struct TabInitialTitleTests {
    @Test func webPagesUseTheHostWithoutWww() throws {
        let url = try #require(URL(string: "https://www.example.com/some/page"))
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.title == "example.com")
    }

    @Test func localFilesUseTheFileNameAndNoFavicon() throws {
        let url = URL(fileURLWithPath: "/tmp/ombre-test.html")
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.title == "ombre-test.html")
        #expect(initial.favicon == nil)
    }

    @Test func urlsWithoutHostThatAreNotFilesAreRejected() throws {
        let url = try #require(URL(string: "about:blank"))

        #expect(TabManager.initialTitleAndFavicon(for: url) == nil)
    }

    /// A site on the local network has no favicon over HTTPS on port 443: asking
    /// for one failed on its certificate each time the tab was drawn.
    @Test(arguments: [
        "http://10.150.150.84:8078/", "http://192.168.1.1/", "http://nas.local/admin", "http://router/",
        "http://[fe80::1]:8080/"
    ])
    func localNetworkSitesHaveNoPlaceholderFavicon(address: String) throws {
        let url = try #require(URL(string: address))
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.favicon == nil)
    }

    @Test func websitesKeepTheirPlaceholderFavicon() throws {
        let url = try #require(URL(string: "http://www.example.com/page"))
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.favicon?.absoluteString == "https://example.com")
    }
}
