import AppKit
import Foundation
import LocalAuthentication
import Security

/// How Ombre keeps passwords safe: Keychain access, unlocking, copying.
enum PasswordKeychain {
    /// Whether the passwords open without asking when macOS can't check who
    /// is there: only on a Mac with no password at all (nothing to ask).
    /// Any other failure keeps them locked (it used to open them).
    static func opensWithoutAsking(whenUnavailable error: Error?) -> Bool {
        guard let error = error as NSError?, error.domain == LAErrorDomain else { return false }
        return error.code == LAError.Code.passcodeNotSet.rawValue
    }

    /// The Keychain items' service, one per copy of the app: they share the
    /// user's keychain, and an item opens without asking only for the copy
    /// that saved it. The tests use their own, never the user's passwords;
    /// a Debug build its own, never the installed app's.
    static func service(isTesting: Bool, isDebug: Bool) -> String {
        if isTesting { return "Ombre Passwords (tests)" }
        return isDebug ? "Ombre Passwords (dev)" : "Ombre Passwords"
    }

    #if DEBUG
        static let isDebugBuild = true
    #else
        static let isDebugBuild = false
    #endif

    /// Deletes every item, going on after a failure: the first failure, if any.
    static func deleteAll(_ references: [Data], delete: (Data) -> OSStatus) -> OSStatus? {
        var failure: OSStatus?
        for reference in references {
            let status = delete(reference)
            if status != errSecSuccess, status != errSecItemNotFound, failure == nil {
                failure = status
            }
        }
        return failure
    }

    /// Clipboard managers' convention (nspasteboard.org): not to be kept in
    /// their history.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// A password copied: marked as one, so clipboard managers skip it.
    @MainActor
    static func writeSensitive(_ value: String, to pasteboard: NSPasteboard) {
        pasteboard.declareTypes([.string, concealedType, transientType], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setData(Data(), forType: concealedType)
        pasteboard.setData(Data(), forType: transientType)
    }
}
