import Foundation
@testable import Ora
import Testing

@MainActor
struct TabInitialTitleTests {
    @Test func webPagesUseTheHostWithoutWww() throws {
        let url = try #require(URL(string: "https://www.example.com/some/page"))
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.title == "example.com")
    }

    @Test func localFilesUseTheFileNameAndNoFavicon() throws {
        let url = URL(fileURLWithPath: "/tmp/ora-test.html")
        let initial = try #require(TabManager.initialTitleAndFavicon(for: url))

        #expect(initial.title == "ora-test.html")
        #expect(initial.favicon == nil)
    }

    @Test func urlsWithoutHostThatAreNotFilesAreRejected() throws {
        let url = try #require(URL(string: "about:blank"))

        #expect(TabManager.initialTitleAndFavicon(for: url) == nil)
    }
}
