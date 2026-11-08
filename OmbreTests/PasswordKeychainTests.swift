import AppKit
import Foundation
import LocalAuthentication
@testable import Ombre
import Testing

/// How passwords are kept safe (SEC-09, SEC-11, SEC-22).
@MainActor
struct PasswordKeychainTests {
    @Test func theyStayLockedWhenMacOSCantCheck() {
        func error(_ code: LAError.Code) -> NSError {
            NSError(domain: LAErrorDomain, code: code.rawValue)
        }
        // A Mac without any password: nothing to ask.
        #expect(PasswordKeychain.opensWithoutAsking(whenUnavailable: error(.passcodeNotSet)))
        // Anything else used to open them.
        #expect(!PasswordKeychain.opensWithoutAsking(whenUnavailable: error(.notInteractive)))
        #expect(!PasswordKeychain.opensWithoutAsking(whenUnavailable: error(.biometryLockout)))
        #expect(!PasswordKeychain.opensWithoutAsking(whenUnavailable: nil))
        #expect(!PasswordKeychain.opensWithoutAsking(
            whenUnavailable: NSError(domain: NSOSStatusErrorDomain, code: LAError.Code.passcodeNotSet.rawValue)
        ))
    }

    /// A space's passwords all go, even after one fails.
    @Test func deletingGoesOnAfterAFailure() {
        let statuses: [OSStatus] = [errSecSuccess, errSecItemNotFound, errSecIO, errSecSuccess, errSecAuthFailed]
        var deleted: [Data] = []
        let references = statuses.indices.map { Data([UInt8($0)]) }
        let failure = PasswordKeychain.deleteAll(references) { reference in
            deleted.append(reference)
            return statuses[Int(reference[0])]
        }
        #expect(deleted == references)
        #expect(failure == errSecIO)
        #expect(PasswordKeychain.deleteAll(references) { _ in errSecItemNotFound } == nil)
    }

    @Test func aCopiedPasswordIsMarkedForClipboardManagers() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasswordKeychainTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        PasswordKeychain.writeSensitive("s3cret", to: pasteboard)
        let types = try #require(pasteboard.types)
        #expect(types.contains(PasswordKeychain.concealedType))
        #expect(types.contains(PasswordKeychain.transientType))
        #expect(pasteboard.string(forType: .string) == "s3cret")
    }
}
