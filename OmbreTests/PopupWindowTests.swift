import Foundation
@testable import Ombre
import Testing

/// "Sign in with…" popups (MOT-09): their title is the site loaded, which a
/// page can't pretend to be; files are downloaded like in a tab.
struct PopupWindowTests {
    @Test func titleIsTheSiteLoadedNotThePagesTitle() {
        #expect(PopupTitle.title(for: URL(string: "https://accounts.google.com/signin?x=1")) == "accounts.google.com")
        #expect(PopupTitle.title(for: URL(string: "http://login.example.net/")) == "Not Secure — login.example.net")
        #expect(PopupTitle.title(for: nil).isEmpty)
    }

    /// A page written into a blank popup by its opener has no host: the
    /// popup shows the opener's site, not nothing (the page's own title,
    /// "accounts.google.com" say, would be all that shows).
    @Test func pageWithoutHostShowsWhereItComesFrom() {
        let opener = URL(string: "https://evil.example/page")
        #expect(PopupTitle.title(for: URL(string: "about:blank"), openerURL: opener) == "evil.example")
        #expect(PopupTitle.title(for: URL(string: "about:blank")) == "about:")
        #expect(PopupTitle.title(for: URL(string: "blob:https://evil.example/1234")) == "evil.example")
        #expect(PopupTitle.title(for: URL(string: "data:text/html,hi")) == "data:")
    }

    @Test func filesAreDownloadedNotShown() throws {
        let url = try #require(URL(string: "https://example.com/file"))
        let page = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:]))
        let attachment = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Disposition": " Attachment; filename=\"a.pdf\""]
        ))
        #expect(!BrowserDownloadPolicy.isDownload(canShowMIMEType: true, response: page))
        #expect(BrowserDownloadPolicy.isDownload(canShowMIMEType: false, response: page))
        #expect(BrowserDownloadPolicy.isDownload(canShowMIMEType: true, response: attachment))
    }
}
