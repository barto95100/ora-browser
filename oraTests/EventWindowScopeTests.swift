import AppKit
@testable import Ora
import Testing

@MainActor
struct EventWindowScopeTests {
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

    @Test func eventInTheSameWindowConcernsIt() {
        let window = makeWindow()
        #expect(EventWindowScope.concerns(eventWindow: window, window: window))
    }

    @Test func eventInAnotherWindowDoesNotConcernIt() {
        #expect(!EventWindowScope.concerns(eventWindow: makeWindow(), window: makeWindow()))
    }

    @Test func eventWithoutWindowDoesNotConcernIt() {
        #expect(!EventWindowScope.concerns(eventWindow: nil, window: makeWindow()))
    }

    @Test func nothingConcernsAWindowNotYetKnown() {
        #expect(!EventWindowScope.concerns(eventWindow: makeWindow(), window: nil))
        #expect(!EventWindowScope.concerns(eventWindow: nil, window: nil))
    }

    /// An extension popup is a child window: Return typed in it must not
    /// confirm a dialog of the browser window.
    @Test func eventInAChildWindowDoesNotConcernIt() {
        let window = makeWindow()
        let child = makeWindow()
        window.addChildWindow(child, ordered: .above)
        defer { window.removeChildWindow(child) }
        #expect(child.parent === window)
        #expect(!EventWindowScope.concerns(eventWindow: child, window: window))
    }

    @Test func eventInAGrandchildWindowDoesNotConcernIt() {
        let window = makeWindow()
        let child = makeWindow()
        let grandchild = makeWindow()
        window.addChildWindow(child, ordered: .above)
        child.addChildWindow(grandchild, ordered: .above)
        defer {
            child.removeChildWindow(grandchild)
            window.removeChildWindow(child)
        }
        #expect(!EventWindowScope.concerns(eventWindow: grandchild, window: window))
    }
}
