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

/// Holding ⌘Q fills the hint; Ombre quits on releasing after that, never
/// while ⌘Q is still down (its repeats would quit the next app).
struct QuitHoldTests {
    private static let qKey: UInt16 = 12

    /// The delay ending with ⌘Q still down arms; it does not quit.
    @Test func heldUntilTheEndArmsWithoutQuitting() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let ending = hold.elapsed(token, isStillHeld: true)
        #expect(ending == .armed)
        #expect(hold.phase == .armed)
    }

    /// Held 3 seconds, then released: quits on the release, once.
    @Test func releasingAfterTheHintIsFullQuits() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        _ = hold.elapsed(token, isStillHeld: true)
        for _ in 0 ..< 30 {
            let repeated = hold.pressed(isRepeat: true)
            #expect(repeated == nil)
        }
        let release = hold.released()
        let again = hold.released()
        #expect(release == .quit)
        #expect(again == .nothing)
        #expect(!hold.isHolding)
    }

    @Test func releasedBeforeTheEndCancels() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let release = hold.released()
        let ending = hold.elapsed(token, isStillHeld: true)
        #expect(release == .cancelled)
        #expect(ending == .stale)
    }

    /// The held key's repeats are absorbed, from the press until the
    /// release: none reaches the menu or another app.
    @Test func repeatsAreAbsorbedDuringTheWholeHold() throws {
        var hold = QuitHold()
        #expect(!hold.absorbs(keyDownOf: Self.qKey, isRepeat: true, heldKeyCode: Self.qKey))
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        #expect(hold.absorbs(keyDownOf: Self.qKey, isRepeat: true, heldKeyCode: Self.qKey))
        _ = hold.elapsed(token, isStillHeld: true)
        #expect(hold.absorbs(keyDownOf: Self.qKey, isRepeat: true, heldKeyCode: Self.qKey))
        // Another key, or a new press, goes through.
        #expect(!hold.absorbs(keyDownOf: 0, isRepeat: true, heldKeyCode: Self.qKey))
        #expect(!hold.absorbs(keyDownOf: Self.qKey, isRepeat: false, heldKeyCode: Self.qKey))
        _ = hold.released()
        #expect(!hold.absorbs(keyDownOf: Self.qKey, isRepeat: true, heldKeyCode: Self.qKey))
    }

    /// The held key repeats: no new delay.
    @Test func repeatsDoNotStartAgain() {
        var hold = QuitHold()
        let first = hold.pressed()
        let repeated = hold.pressed(isRepeat: true)
        #expect(first != nil)
        #expect(repeated == nil)
    }

    /// Pressed, released, pressed again: the first press's delay ending
    /// does nothing, only the second one's arms.
    @Test func anEarlierPressNeverArms() throws {
        var hold = QuitHold()
        let firstPress = hold.pressed()
        let first = try #require(firstPress)
        _ = hold.released()
        let secondPress = hold.pressed()
        let second = try #require(secondPress)
        let firstEnding = hold.elapsed(first, isStillHeld: true)
        let secondEnding = hold.elapsed(second, isStillHeld: true)
        #expect(firstEnding == .stale)
        #expect(secondEnding == .armed)
    }

    /// A new press (not a repeat) during a hold: a release we did not see.
    /// It starts again, and the old delay does not arm.
    @Test func aNewPressStartsAgain() throws {
        var hold = QuitHold()
        let firstPress = hold.pressed()
        let first = try #require(firstPress)
        _ = hold.elapsed(first, isStillHeld: true)
        let secondPress = hold.pressed(isRepeat: false)
        let second = try #require(secondPress)
        #expect(hold.phase == .holding)
        let firstEnding = hold.elapsed(first, isStillHeld: true)
        let secondEnding = hold.elapsed(second, isStillHeld: true)
        #expect(firstEnding == .stale)
        #expect(secondEnding == .armed)
    }

    /// ⌘ or the key let go without us seeing it: no arming, the hold ends,
    /// and the next ⌘Q starts again.
    @Test func keysNoLongerDownDoNotArm() throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        let ending = hold.elapsed(token, isStillHeld: false)
        #expect(ending == .cancelled)
        #expect(!hold.isHolding)
        let next = hold.pressed()
        #expect(next != nil)
    }

    /// Ombre leaves the front during the hold: nothing happens, even once
    /// the hint is full, and releasing afterwards does not quit.
    @Test(arguments: [false, true])
    func leavingOmbreNeverQuits(isArmed: Bool) throws {
        var hold = QuitHold()
        let tokenPress = hold.pressed()
        let token = try #require(tokenPress)
        if isArmed { _ = hold.elapsed(token, isStillHeld: true) }
        let abandoned = hold.abandoned()
        let release = hold.released()
        #expect(abandoned)
        #expect(release == .nothing)
    }

    @Test func releasingWithoutAHoldIsNothing() {
        var hold = QuitHold()
        let release = hold.released()
        #expect(release == .nothing)
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
