import AppKit
@testable import Ombre
import Testing

@MainActor
struct NotificationWindowScopeTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func commandForTheSameWindowConcernsIt() {
        let window = makeWindow()
        #expect(NotificationWindowScope.concerns(target: window, window: window, keyWindow: nil))
    }

    /// ⌘S in one window must not toggle the sidebar of another window.
    @Test func commandForAnotherWindowDoesNotConcernIt() {
        let window = makeWindow()
        #expect(!NotificationWindowScope.concerns(target: makeWindow(), window: window, keyWindow: nil))
    }

    /// The window of the view wins over the key window.
    @Test func commandForTheKeyWindowDoesNotConcernAnotherKnownWindow() {
        let keyWindow = makeWindow()
        #expect(!NotificationWindowScope.concerns(target: keyWindow, window: makeWindow(), keyWindow: keyWindow))
    }

    @Test func commandWithoutWindowConcernsNone() {
        let window = makeWindow()
        #expect(!NotificationWindowScope.concerns(target: nil, window: window, keyWindow: window))
    }

    @Test func commandWhoseObjectIsNotAWindowConcernsNone() {
        let window = makeWindow()
        #expect(!NotificationWindowScope.concerns(target: "window", window: window, keyWindow: window))
    }

    @Test func viewWithoutWindowYetStandsForTheKeyWindow() {
        let keyWindow = makeWindow()
        #expect(NotificationWindowScope.concerns(target: keyWindow, window: nil, keyWindow: keyWindow))
        #expect(!NotificationWindowScope.concerns(target: makeWindow(), window: nil, keyWindow: keyWindow))
    }

    @Test func nothingConcernsAViewWithoutWindowWhenNoWindowIsKey() {
        #expect(!NotificationWindowScope.concerns(target: makeWindow(), window: nil, keyWindow: nil))
    }
}
