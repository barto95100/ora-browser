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
    @MainActor
    private final class Setup {
        let little = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let browser = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        var key: NSWindow?
        /// Front to back.
        var order: [NSWindow] = []
        var isActive = true
        var eventType: NSEvent.EventType?
        var broughtBack = 0
    }

    private func makeGuard(_ setup: Setup) -> LittleOmbreFrontGuard {
        setup.little.isReleasedWhenClosed = false
        setup.browser.isReleasedWhenClosed = false
        setup.key = setup.little
        setup.order = [setup.little, setup.browser]
        return LittleOmbreFrontGuard(
            little: setup.little,
            browserWindow: setup.browser,
            isBrowserWindow: { [browser = setup.browser] in $0 === browser },
            currentEventType: { setup.eventType },
            keyWindow: { setup.key },
            orderedWindows: { setup.order },
            isActive: { setup.isActive },
            bringBack: { setup.broughtBack += 1 }
        )
    }

    /// The browser window raised above Little Ombre, which stays key (what
    /// the app's activation did).
    private func browserRaisedAbove(_ setup: Setup) {
        setup.order = [setup.browser, setup.little]
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: setup.little)
    }

    private func browserBecomesKey(_ setup: Setup) {
        setup.key = setup.browser
        setup.order = [setup.browser, setup.little]
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

    @Test func theBrowserWindowRaisedAboveLittleOmbreStillKeyIsUndone() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        browserRaisedAbove(setup)
        #expect(setup.broughtBack == 1)
        guarded.stop()
    }

    @Test func aCoveredOrUncoveredWindowWithLittleOmbreOnTopIsLeftAlone() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: setup.browser)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: setup.little)
        #expect(setup.broughtBack == 0)
        guarded.stop()
    }

    @Test func anotherWindowsOcclusionIsIgnored() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        setup.order = [setup.browser, setup.little]
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: other)
        #expect(setup.broughtBack == 0)
        guarded.stop()
    }

    @Test func neverMoreThanAFewBringBacks() {
        // Something that keeps raising the browser window: given up.
        let setup = Setup()
        let guarded = makeGuard(setup)
        for _ in 0 ..< 10 {
            browserRaisedAbove(setup)
        }
        #expect(setup.broughtBack == LittleOmbreFrontGuard.maximumBringBacks)
        #expect(guarded.isOver)
    }

    @Test func littleOmbreIsAboveWhenNoBrowserWindowComesFirst() {
        let setup = Setup()
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        let isBrowser: (NSWindow) -> Bool = { [browser = setup.browser] in $0 === browser }
        #expect(LittleOmbreFrontGuard.isAbove(
            setup.little,
            in: [other, setup.little, setup.browser],
            isBrowserWindow: isBrowser
        ))
        #expect(!LittleOmbreFrontGuard.isAbove(
            setup.little,
            in: [setup.browser, setup.little],
            isBrowserWindow: isBrowser
        ))
        // Not on screen at all: not above.
        #expect(!LittleOmbreFrontGuard.isAbove(setup.little, in: [setup.browser], isBrowserWindow: isBrowser))
        #expect(!LittleOmbreFrontGuard.isAbove(setup.little, in: [], isBrowserWindow: isBrowser))
    }

    @Test func nothingIsTakenBackWhileOmbreIsInactive() {
        // Its activation still to come, or the user in another app.
        let setup = Setup()
        let guarded = makeGuard(setup)
        setup.isActive = false
        setup.key = nil
        browserRaisedAbove(setup)
        #expect(setup.broughtBack == 0)
        #expect(!guarded.isOver)
        guarded.stop()
    }

    @Test func leavingOmbreEndsTheGuard() {
        let setup = Setup()
        let guarded = makeGuard(setup)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(guarded.isOver)
        browserRaisedAbove(setup)
        #expect(setup.broughtBack == 0)
    }

    @Test func aChildWindowOfLittleOmbreCountsAsLittleOmbre() {
        let setup = Setup()
        let child = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        child.isReleasedWhenClosed = false
        setup.little.addChildWindow(child, ordered: .above)
        defer { setup.little.removeChildWindow(child) }
        #expect(LittleOmbreFrontGuard.belongs(child, to: setup.little))
        #expect(!LittleOmbreFrontGuard.belongs(setup.browser, to: setup.little))
        let guarded = makeGuard(setup)
        setup.key = child
        setup.order = [child, setup.little, setup.browser]
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: setup.little)
        #expect(setup.broughtBack == 0)
        guarded.stop()
    }
}
