import Foundation
@testable import Ora
import Testing

struct PageAnchorTests {
    @Test func theFirstWordsAreKept() {
        #expect(PageAnchor.excerpt("  Hello   big\nworld ", words: 2) == "Hello big")
    }

    @Test func theLinkLeadsToTheWords() throws {
        let page = try #require(URL(string: "https://example.com/a?b=1"))
        let url = PageAnchor.url(page, scrolledTo: "Écran - test, (deux) & co")
        #expect(url.absoluteString ==
            "https://example.com/a?b=1#:~:text=%C3%89cran%20%2D%20test%2C%20%28deux%29%20%26%20co")
    }

    @Test func aPageFragmentIsKept() throws {
        let page = try #require(URL(string: "https://example.com/doc#part"))
        #expect(PageAnchor.url(page, scrolledTo: "word").absoluteString == "https://example.com/doc#part:~:text=word")
    }

    @Test func anOldTextDirectiveIsReplaced() throws {
        let page = try #require(URL(string: "https://example.com/#:~:text=old"))
        #expect(PageAnchor.url(page, scrolledTo: "new").absoluteString == "https://example.com/#:~:text=new")
    }

    @Test func noWordsLeavesThePage() throws {
        let page = try #require(URL(string: "https://example.com/"))
        #expect(PageAnchor.url(page, scrolledTo: "  ") == page)
    }
}
