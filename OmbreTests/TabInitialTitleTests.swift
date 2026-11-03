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
}
