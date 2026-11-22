import AppKit
@testable import Ombre
import Testing

/// Little Ombre opened for a link from another app stays in front: a browser
/// window made key just after, without the user, gives the front back.
@MainActor
struct LittleOmbreFrontGuardTests {
    // MARK: - The decision

    @Test func aBrowserWindowMadeKeyWithoutTheUserGivesTheFrontBack() {
        let response = LittleOmbreFrontGuard.response(
            to: .windowBecameKey(isBrowserWindow: true), littleIsInFront: false, byUser: false,
            elapsed: .milliseconds(50)
        )
        #expect(response == .bringBack)
    }

    @Test func anotherWindowMadeKeyIsLeftAlone() {
        // A panel, the settings, a page's sheet: not the browser window.
        let response = LittleOmbreFrontGuard.response(
            to: .windowBecameKey(isBrowserWindow: false), littleIsInFront: false, byUser: false, elapsed: .zero
        )
        #expect(response == .keep)
    }

    @Test func theUsersClickOrKeyEndsTheGuard() {
        for change in [LittleOmbreFrontGuard.Change.windowBecameKey(isBrowserWindow: true), .settled] {
            let response = LittleOmbreFrontGuard.response(
                to: change, littleIsInFront: false, byUser: true, elapsed: .zero
            )
            #expect(response == .stop)
        }
    }

    @Test func afterTheGuardsTimeNothingIsTaken() {
        let response = LittleOmbreFrontGuard.response(
            to: .windowBecameKey(isBrowserWindow: true),
            littleIsInFront: false,
            byUser: false,
            elapsed: LittleOmbreFrontGuard.duration
        )
        #expect(response == .stop)
    }

    @Test func activationWithLittleOmbreBehindGivesTheFrontBack() {
        #expect(LittleOmbreFrontGuard.response(
            to: .settled, littleIsInFront: false, byUser: false, elapsed: .zero
        ) == .bringBack)
        #expect(LittleOmbreFrontGuard.response(
            to: .settled, littleIsInFront: true, byUser: false, elapsed: .zero
        ) == .keep)
    }

    @Test func clicksAndKeysAreTheUsers() {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown] {
            #expect(LittleOmbreFrontGuard.isUserEvent(type))
        }
        for type in [NSEvent.EventType.appKitDefined, .systemDefined, .applicationDefined, .mouseMoved] {
            #expect(!LittleOmbreFrontGuard.isUserEvent(type))
        }
        #expect(!LittleOmbreFrontGuard.isUserEvent(nil))
    }

    // MARK: - The guard, with windows never shown

    /// A guard over two windows never put on screen, with the key window and
    /// the event being handled as the test sets them.
    private final class Setup {
        let little = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let browser = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        var key: NSWindow?
        var eventType: NSEvent.EventType?
        var broughtBack = 0
    }

    private func makeGuard(_ setup: Setup) -> LittleOmbreFrontGuard {
        setup.little.isReleasedWhenClosed = false
        setup.browser.isReleasedWhenClosed = false
        setup.key = setup.little
        return LittleOmbreFrontGuard(
            little: setup.little,
            browserWindow: setup.browser,
            isBrowserWindow: { [browser = setup.browser] in $0 === browser },
            currentEventType: { setup.eventType },
            keyWindow: { setup.key },
            isActive: { false },
            bringBack: { setup.broughtBack += 1 }
        )
    }

    private func browserBecomesKey(_ setup: Setup) {
        setup.key = setup.browser
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: setup.browser)
    }

    @Test func theBrowserWindowTakingTheKeyAfterTheLinkIsUndone() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        browserBecomesKey(setup)
        #expect(setup.broughtBack == 1)
        #expect(!guarded.isOver)
        guarded.stop()
    }

    @Test func theBrowserWindowClickedByTheUserKeepsTheKey() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        setup.eventType = .leftMouseDown
        browserBecomesKey(setup)
        #expect(setup.broughtBack == 0)
        #expect(guarded.isOver)
        // Over: a later change is left alone.
        setup.eventType = nil
        browserBecomesKey(setup)
        #expect(setup.broughtBack == 0)
    }

    @Test func aStoppedGuardTakesNothingBack() {
        // "Open in Ombre", a tab opened from Little Ombre, its close.
        let setup = Setup()
        let guarded = makeGuard(setup)
        guarded.stop()
        browserBecomesKey(setup)
        #expect(setup.broughtBack == 0)
    }

    @Test func littleOmbreStillKeyIsLeftAlone() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: setup.little)
        #expect(setup.broughtBack == 0)
        #expect(!guarded.isOver)
        guarded.stop()
    }
}
