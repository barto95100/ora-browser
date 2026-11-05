import Foundation
@testable import Ombre
import Testing

/// A page on a port browsers never open (ssh, mail…): an error page, like
/// Safari, not a blank page that pretends to be loaded.
struct RestrictedPortTests {
    @Test func portsBrowsersNeverOpen() throws {
        #expect(try RestrictedPort.isRestricted(#require(URL(string: "http://127.0.0.1:9/"))))
        #expect(try RestrictedPort.isRestricted(#require(URL(string: "https://example.com:22/"))))
        #expect(try !RestrictedPort.isRestricted(#require(URL(string: "http://example.com:8080/"))))
        #expect(try !RestrictedPort.isRestricted(#require(URL(string: "https://example.com/"))))
        #expect(try !RestrictedPort.isRestricted(#require(URL(string: "file:///tmp/a.html"))))
    }
}

extension TabManagerTests {
    @MainActor
    struct RestrictedPortPage {
        @Test func restrictedPortShowsAnErrorPage() async throws {
            try await TabManagerTestWindow.run { window in
                let tab = try await window.openLoaded("page")
                let blocked = try #require(URL(string: "http://127.0.0.1:9/"))

                tab.loadURL(blocked.absoluteString)
                await window.waitUntil("error page") { tab.runtime?.navigationFailure != nil }

                let failure = try #require(tab.runtime?.navigationFailure)
                #expect((failure.error as NSError).code == RestrictedPort.errorCode)
                #expect(failure.url == blocked)
                #expect(tab.url != URL(string: "about:blank"))
            }
        }
    }
}
