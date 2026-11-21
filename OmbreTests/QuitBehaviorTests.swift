import AppKit
@testable import Ombre
import Testing

/// ⌘Q held, asked or at once; the menu always quits at once.
struct QuitDecisionTests {
    @Test func holdingIsTheDefault() {
        #expect(QuitBehavior.defaultValue == .holdKey)
    }

    @Test(arguments: QuitBehavior.allCases)
    func theMenuTheDockAndLoggingOutQuitAtOnce(behavior: QuitBehavior) {
        #expect(QuitDecision.decide(behavior: behavior, isQuitKey: false, isConfirmed: false) == .quit)
    }

    @Test func theQuitKeyFollowsTheSetting() {
        #expect(QuitDecision.decide(behavior: .holdKey, isQuitKey: true, isConfirmed: false) == .hold)
        #expect(QuitDecision.decide(behavior: .ask, isQuitKey: true, isConfirmed: false) == .ask)
        #expect(QuitDecision.decide(behavior: .immediately, isQuitKey: true, isConfirmed: false) == .quit)
    }

    /// Once ⌘Q was held long enough, the quit it starts goes through.
    @Test(arguments: QuitBehavior.allCases)
    func aConfirmedQuitGoesThrough(behavior: QuitBehavior) {
        #expect(QuitDecision.decide(behavior: behavior, isQuitKey: true, isConfirmed: true) == .quit)
    }

    /// The decision has nothing of a window: ⌘Q is the same in Little
    /// Ombre, a browser window or the settings (18/11). A key press with ⌘
    /// is the shortcut; a click in the menu is not.
    @Test func onlyAKeyPressWithCommandIsTheQuitKey() throws {
        let quitKey = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
        ))
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        ))
        let release = try #require(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
            context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
        ))
        #expect(QuitDecision.isQuitKey(quitKey))
        #expect(!QuitDecision.isQuitKey(click))
        #expect(!QuitDecision.isQuitKey(release))
        #expect(!QuitDecision.isQuitKey(nil))
        // The Dock or logging out, while the last event was ⌘Q.
        #expect(!QuitDecision.isQuitKey(quitKey, isAppleEvent: true))
    }
}

/// Holding ⌘Q about a second quits; releasing before does nothing.
struct QuitHoldTests {
    @Test func heldUntilTheEndQuits() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let ending = hold.elapsed(token, isStillHeld: true)
        #expect(ending == .quit)
        #expect(!hold.isHolding)
    }

    @Test func releasedBeforeTheEndDoesNothing() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let cancels = hold.released()
        let ending = hold.elapsed(token, isStillHeld: true)
        #expect(cancels)
        #expect(ending == .stale)
    }

    /// The held key repeats: no new delay.
    @Test func repeatsDoNotStartAgain() {
        var hold = QuitHold()
        let first = hold.pressed()
        let repeated = hold.pressed()
        #expect(first != nil)
        #expect(repeated == nil)
    }

    /// Pressed, released, pressed again: the first press's delay ending
    /// does not quit, only the second one's.
    @Test func anEarlierPressNeverQuits() throws {
        var hold = QuitHold()
        let firstPress = hold.pressed()
        let first = try #require(firstPress)
        _ = hold.released()
        let secondPress = hold.pressed()
        let second = try #require(secondPress)
        let firstEnding = hold.elapsed(first, isStillHeld: true)
        let secondEnding = hold.elapsed(second, isStillHeld: true)
        #expect(firstEnding == .stale)
        #expect(secondEnding == .quit)
    }

    /// ⌘ or the key let go without us seeing it: no quit, the hold ends,
    /// and the next ⌘Q starts again.
    @Test func keysNoLongerDownDoNotQuit() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let ending = hold.elapsed(token, isStillHeld: false)
        #expect(ending == .cancelled)
        #expect(!hold.isHolding)
        let next = hold.pressed()
        #expect(next != nil)
    }

    @Test func releasingWithoutAHoldIsNothing() {
        var hold = QuitHold()
        let cancels = hold.released()
        #expect(!cancels)
    }

    @Test func aboutASecond() {
        #expect((0.8 ... 1.2).contains(QuitHold.duration))
    }
}

struct QuitConfirmationTextTests {
    @Test(arguments: [(2, 14), (1, 1), (1, 0)])
    func itSaysHowManyWindowsAndTabs(windows: Int, tabs: Int) {
        let text = QuitConfirmationText.message(windows: windows, tabs: tabs)
        #expect(text.contains(String(localized: "\(windows) windows")))
        #expect(text.contains(String(localized: "\(tabs) tabs")))
    }

    /// One of each: the singular.
    @Test func oneWindowIsSingular() {
        let one = String(localized: "\(1) windows")
        let two = String(localized: "\(2) windows")
        #expect(one.count < two.count)
    }
}
