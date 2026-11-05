import Foundation
@testable import Ombre
import Testing
import WebKit

/// One session per private window, like Safari and Arc: its tabs share
/// cookies and logins; another private window, or the same one reopened,
/// starts from nothing.
@MainActor
struct PrivateSessionTests {
    private let engine = BrowserEngine.shared

    @Test func aPrivateWindowsTabsShareOneStore() {
        let window = UUID()
        let first = engine.makeProfile(identifier: UUID(), isPrivate: true, privateSession: window)
        let second = engine.makeProfile(identifier: UUID(), isPrivate: true, privateSession: window)

        #expect(first.dataStore === second.dataStore)
        #expect(!first.dataStore.isPersistent)
        engine.endPrivateSession(window)
    }

    @Test func eachPrivateWindowHasItsOwnStore() {
        let firstWindow = UUID()
        let secondWindow = UUID()
        let space = UUID()

        let first = engine.makeProfile(identifier: space, isPrivate: true, privateSession: firstWindow)
        let second = engine.makeProfile(identifier: space, isPrivate: true, privateSession: secondWindow)

        #expect(first.dataStore !== second.dataStore)
        engine.endPrivateSession(firstWindow)
        engine.endPrivateSession(secondWindow)
    }

    @Test func aClosedPrivateWindowsSessionIsGone() {
        let window = UUID()
        let before = engine.makeProfile(identifier: UUID(), isPrivate: true, privateSession: window)
        #expect(engine.hasPrivateSession(window))

        engine.endPrivateSession(window)

        #expect(!engine.hasPrivateSession(window))
        let after = engine.makeProfile(identifier: UUID(), isPrivate: true, privateSession: window)
        #expect(before.dataStore !== after.dataStore)
        engine.endPrivateSession(window)
    }

    @Test func eachProfileKeepsItsSpace() {
        let window = UUID()
        let space = UUID()

        let profile = engine.makeProfile(identifier: space, isPrivate: true, privateSession: window)

        // The space's content rules still apply to its pages.
        #expect(profile.identifier == space)
        engine.endPrivateSession(window)
    }

    @Test func twoTabsOfAPrivateWindowShareTheirStore() async throws {
        try await TabManagerTestWindow.run { window in
            let space = window.createSpace("Private")
            let first = window.addUnloadedTab("first", order: 1, in: space)
            let second = window.addUnloadedTab("second", order: 2, in: space)

            let firstPage = first.makeBrowserPage(isPrivate: true)
            let secondPage = second.makeBrowserPage(isPrivate: true)

            #expect(firstPage.webView.configuration.websiteDataStore
                === secondPage.webView.configuration.websiteDataStore)
            firstPage.teardown()
            secondPage.teardown()
            engine.endPrivateSession(window.tabManager.privateSessionID)
        }
    }
}
