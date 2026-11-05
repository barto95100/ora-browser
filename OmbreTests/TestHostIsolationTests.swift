import AppKit
import Foundation
@testable import Ombre
import SwiftData
import Testing

/// The tests run inside the app: it must keep away from the user's data
/// (database, windows, preferences, files, Keychain).
@MainActor
struct TestHostIsolationTests {
    @Test func theAppKnowsItRunsTheTests() {
        #expect(TestHost.isActive)
    }

    @Test func theRealDatabaseIsNeverOpened() {
        let container = DatabaseRecovery.mainContainer

        let inMemory = container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        #expect(inMemory)
        #expect(!DatabaseRecovery.hasOpenedDatabaseOnDisk)
    }

    @Test func itHasItsOwnIdentityAndContainer() {
        // Not the Debug app's: its preferences and files are its own.
        #expect(Bundle.main.bundleIdentifier == "com.barto95100.ora.tests")
        #expect(NSHomeDirectory().contains("com.barto95100.ora.tests"))
    }

    @Test func noWindowIsOpen() {
        #expect(BrowserWindows.browsing.allObjects.isEmpty)
        // No browsing window, assistant, settings nor restored window.
        #expect(NSApp.windows.filter(\.isVisible).isEmpty)
    }

    @Test func passwordsUseTheirOwnKeychainService() {
        #expect(PasswordManagerService.shared.serviceName != "Ombre Passwords")
    }
}
