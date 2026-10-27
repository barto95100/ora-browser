import SwiftUI
@testable import Ora
import Testing

struct ShortcutDoublePressTests {
    private let toggleSidebar = KeyChord(keyEquivalent: "s", modifiers: [.command])
    private let find = KeyChord(keyEquivalent: "f", modifiers: [.command])

    @Test func singlePressIsNotForced() {
        var detector = ShortcutDoublePressDetector()

        let forced = detector.keyPressed(toggleSidebar, at: 10)

        #expect(!forced)
    }

    @Test func quickSecondPressIsForcedWhenThePageKeptTheFirst() {
        var detector = ShortcutDoublePressDetector()
        _ = detector.keyPressed(toggleSidebar, at: 10)

        let forced = detector.keyPressed(toggleSidebar, at: 10.3)

        #expect(forced)
    }

    @Test func secondPressIsNotForcedWhenOraHandledTheFirst() {
        var detector = ShortcutDoublePressDetector()
        _ = detector.keyPressed(toggleSidebar, at: 10)
        detector.appHandledShortcut()

        let forced = detector.keyPressed(toggleSidebar, at: 10.3)

        #expect(!forced)
    }

    @Test func slowSecondPressIsNotForced() {
        var detector = ShortcutDoublePressDetector()
        _ = detector.keyPressed(toggleSidebar, at: 10)

        let forced = detector.keyPressed(toggleSidebar, at: 11)

        #expect(!forced)
    }

    @Test func differentShortcutsDoNotCombine() {
        var detector = ShortcutDoublePressDetector()
        _ = detector.keyPressed(toggleSidebar, at: 10)

        let forced = detector.keyPressed(find, at: 10.2)

        #expect(!forced)
    }

    @Test func aThirdQuickPressStartsOver() {
        var detector = ShortcutDoublePressDetector()
        _ = detector.keyPressed(toggleSidebar, at: 10)
        _ = detector.keyPressed(toggleSidebar, at: 10.2)

        let forced = detector.keyPressed(toggleSidebar, at: 10.4)

        #expect(!forced)
    }
}
