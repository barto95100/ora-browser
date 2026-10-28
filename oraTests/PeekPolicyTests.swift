import AppKit
@testable import Ora
import Testing

struct PeekPolicyTests {
    private func opens(
        _ destination: String,
        from page: URL? = URL(string: "https://mail.google.com/inbox"),
        tab: TabType = .pinned,
        click: Bool = true,
        modifiers: NSEvent.ModifierFlags = [],
        enabled: Bool = true
    ) -> Bool {
        PeekPolicy.opensInPeek(
            tabType: tab,
            isLinkClick: click,
            modifierFlags: modifiers,
            from: page,
            to: URL(string: destination)!,
            isEnabled: enabled
        )
    }

    @Test func aLinkToAnotherSiteFromAPinnedOrFavoriteTabOpensInPeek() {
        #expect(opens("https://github.com/the-ora/browser"))
        #expect(opens("https://github.com/the-ora/browser", tab: .fav))
    }

    @Test func aLinkWithinTheSameSiteStaysInTheTab() {
        #expect(!opens("https://docs.google.com/document/1"))
        #expect(!opens("https://mail.google.com/settings"))
    }

    @Test func regularTabsAndOtherNavigationsNeverOpenPeek() {
        #expect(!opens("https://github.com", tab: .normal))
        #expect(!opens("https://github.com", click: false))
        #expect(!opens("https://github.com", enabled: false))
        #expect(!opens("https://github.com", modifiers: [.command]))
        #expect(!opens("mailto:someone@example.com"))
    }

    @Test func sitesFollowThePublicSuffixList() throws {
        #expect(try WebSite.isSameSite(
            #require(URL(string: "https://a.bbc.co.uk")),
            #require(URL(string: "https://www.bbc.co.uk"))
        ))
        #expect(try !WebSite.isSameSite(
            #require(URL(string: "https://alice.github.io")),
            #require(URL(string: "https://bob.github.io"))
        ))
    }
}
