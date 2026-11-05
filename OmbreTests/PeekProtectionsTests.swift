import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// Peek follows its space's protections like a tab: an exempted site
    /// isn't blocked, tracking parameters are taken off links (MOT-19).
    @MainActor
    struct PeekProtections {
        @Test func peekFollowsTheSpacesProtections() async throws {
            try await TabManagerTestWindow.run { window in
                let opener = try await window.openLoaded("opener")
                let space = try window.activeSpace
                var settings = SettingsStore.shared.privacySettings(for: space.id)
                settings.blockThirdPartyTrackers = true
                settings.exemptSites = ["exempt.example"]
                SettingsStore.shared.setPrivacySettings(settings, for: space.id)

                opener.openPeek(TabManagerTestWindow.url("peek"))
                let peek = try #require(window.tabManager.peek)
                defer { window.tabManager.closePeek() }
                let delegate = try #require(peek.page.delegate)
                let tracked = try #require(URL(string: "https://shop.example/item?utm_source=mail"))
                let exempted = try #require(URL(string: "https://www.exempt.example/item?utm_source=mail"))

                #expect(delegate.browserPage(peek.page, removesLinkTrackingFrom: tracked))
                #expect(!delegate.browserPage(peek.page, removesLinkTrackingFrom: exempted))
                #expect(delegate.browserPage(peek.page, allowsContentBlockingFor: tracked))
                #expect(!delegate.browserPage(peek.page, allowsContentBlockingFor: exempted))
            }
        }
    }
}
