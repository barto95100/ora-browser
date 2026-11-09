import Foundation
@testable import Ombre
import Security
import Testing

/// Saving a password for real, in the Keychain the sandboxed app can reach
/// (SEC-10). Its own service: never the user's passwords.
@MainActor
@Suite(.serialized)
struct PasswordStorageTests {
    let service = PasswordManagerService.shared

    private func removeSaved(on url: URL) throws {
        for entry in service.entries where entry.origin == PasswordManagerService.normalizedOrigin(from: url) {
            try service.delete(entry)
        }
    }

    /// It used to fail with -34018: an iCloud item needs an entitlement the
    /// app can't have.
    @Test func aSavedPasswordCanBeReadBack() throws {
        let url = try #require(URL(string: "https://storage-test-\(UUID().uuidString.lowercased()).example"))
        defer { try? removeSaved(on: url) }
        try service.upsertCredential(for: url, username: "ludo", password: "s3cret-1", containerID: nil)
        let entry = try #require(service.matchingEntries(for: url).first)
        #expect(entry.username == "ludo")
        #expect(try service.revealPassword(for: entry) == "s3cret-1")

        // Changed in place, not added again.
        try service.upsertCredential(for: url, username: "ludo", password: "s3cret-2", containerID: nil)
        let entries = service.matchingEntries(for: url)
        #expect(entries.count == 1)
        #expect(try service.revealPassword(for: #require(entries.first)) == "s3cret-2")
    }

    /// On this Mac only: never sent to iCloud.
    @Test func aSavedPasswordStaysOnThisMac() throws {
        let url = try #require(URL(string: "https://local-test-\(UUID().uuidString.lowercased()).example"))
        defer { try? removeSaved(on: url) }
        try service.upsertCredential(for: url, username: "ludo", password: "s3cret", containerID: nil)
        let entry = try #require(service.matchingEntries(for: url).first)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecValuePersistentRef as String: entry.persistentReference,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect((attributes[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
    }

    /// A failure says its status, to find it in the logs.
    @Test func aFailureSaysItsStatus() {
        let message = PasswordManagerError.keychainStatus(errSecMissingEntitlement).localizedDescription
        #expect(message.contains("-34018"))
        #expect(PasswordAutofillCoordinator.saveFailureTitle(host: "example.com").contains("example.com"))
    }

    /// The tests, a Debug build and the installed app each keep their own.
    @Test func eachCopyOfTheAppHasItsOwnPasswords() {
        let services = [
            PasswordKeychain.service(isTesting: true, isDebug: true),
            PasswordKeychain.service(isTesting: false, isDebug: true),
            PasswordKeychain.service(isTesting: false, isDebug: false)
        ]
        #expect(Set(services).count == 3)
        #expect(PasswordKeychain.service(isTesting: false, isDebug: false) == "Ombre Passwords")
        #expect(service.serviceName == "Ombre Passwords (tests)")
    }
}
