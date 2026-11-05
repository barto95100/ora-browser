@testable import Ombre
import Testing

/// ⌘W closes the tab of a browser window, and any other window itself
/// (the settings window used to keep ⌘W for a tab it doesn't have).
struct CloseCommandTests {
    @Test func closesTheTabOfABrowserWindow() {
        #expect(CloseCommand.action(hasKeyWindow: true, isBrowserWindow: true) == .closeTab)
    }

    @Test func closesAnyOtherWindow() {
        #expect(CloseCommand.action(hasKeyWindow: true, isBrowserWindow: false) == .closeWindow)
    }

    @Test func doesNothingWithoutAWindow() {
        #expect(CloseCommand.action(hasKeyWindow: false, isBrowserWindow: false) == .nothing)
    }
}
