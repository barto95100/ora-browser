import Foundation
@testable import Ombre
import Testing

/// What VoiceOver says of the sidebar's tabs and the toolbar's buttons (INT-11).
struct TabAccessibilityTests {
    @Test func tabIsNamedByItsTitleElseItsSite() throws {
        let url = try #require(URL(string: "https://www.example.com/page"))
        #expect(TabAccessibility.label(title: "Example", url: url) == "Example")
        #expect(TabAccessibility.label(title: "  ", url: url) == "www.example.com")
    }

    @Test func tabSaysWhetherItIsLoadedOrPlaying() {
        #expect(TabAccessibility.value(isLoaded: false, isPlayingMedia: false) == "Not loaded")
        #expect(TabAccessibility.value(isLoaded: true, isPlayingMedia: true) == "Playing audio")
        #expect(TabAccessibility.value(isLoaded: true, isPlayingMedia: false).isEmpty)
    }

    @Test func toolbarButtonsHaveNames() {
        #expect(URLBarButton.label(for: "chevron.left") == "Back")
        #expect(URLBarButton.label(for: "chevron.right") == "Forward")
        #expect(URLBarButton.label(for: "arrow.clockwise") == "Reload")
        #expect(URLBarButton.label(for: "sidebar.right") == "Toggle Sidebar")
        // Other symbols: SwiftUI's own name for them.
        #expect(URLBarButton.label(for: "star") == nil)
    }
}
