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
    }
}

/// Holding ⌘Q about a second quits; releasing before does nothing.
struct QuitHoldTests {
    @Test func heldUntilTheEndQuits() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let quits = hold.elapsed(token, isCommandDown: true)
        #expect(quits)
        #expect(!hold.isHolding)
    }

    @Test func releasedBeforeTheEndDoesNothing() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let cancels = hold.released()
        let quits = hold.elapsed(token, isCommandDown: true)
        #expect(cancels)
        #expect(!quits)
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
        let firstQuits = hold.elapsed(first, isCommandDown: true)
        let secondQuits = hold.elapsed(second, isCommandDown: true)
        #expect(!firstQuits)
        #expect(secondQuits)
    }

    /// ⌘ let go without us seeing it: no quit.
    @Test func commandNoLongerDownDoesNotQuit() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let quits = hold.elapsed(token, isCommandDown: false)
        #expect(!quits)
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
    @Test func itSaysHowManyWindowsAndTabs() {
        let text = QuitConfirmationText.message(windows: 2, tabs: 14)
        #expect(text.contains("2"))
        #expect(text.contains("14"))
    }
}
