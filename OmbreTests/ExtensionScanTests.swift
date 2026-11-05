import AppKit
import Foundation
@testable import Ombre
import Testing

/// The installed apps are scanned for Safari extensions only while the
/// extensions' settings are open, not at every return to Ombre.
@MainActor
@Suite(.serialized)
struct ExtensionScanTests {
    @Test func returningToOmbreDoesNotScanWithTheSettingsClosed() {
        guard #available(macOS 15.4, *) else { return }
        let manager = WebExtensionsManager.shared
        // A restored settings window could be showing them.
        guard manager.candidateViewers == 0 else { return }
        let before = manager.scansStarted

        // As when the user comes back to Ombre (⌘Tab).
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)

        #expect(manager.scansStarted == before)
    }

    @Test func theSettingsScanWhenShownAndOnReturn() {
        guard #available(macOS 15.4, *) else { return }
        let manager = WebExtensionsManager.shared
        let before = manager.scansStarted

        let viewers = manager.candidateViewers

        manager.candidatesAppeared()
        manager.appBecameActive()
        manager.candidatesDisappeared()

        #expect(manager.scansStarted == before + 2)
        #expect(manager.candidateViewers == viewers)
    }
}
