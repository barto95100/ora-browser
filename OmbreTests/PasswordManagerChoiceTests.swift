import Foundation
@testable import Ombre
import Testing

/// Settings › Passwords › "Password manager": Ombre's passwords, or a
/// password manager extension installed and enabled, which Ombre then
/// leaves the passwords to. A choice of the tests' own, never the app's.
@MainActor
struct PasswordManagerChoiceTests {
    final class Choice: PasswordManagerChoiceSettings {
        var passwordsEnabled = true
        var passwordManagerExtensionID: String?
    }

    @Test func ombreThenEachExtension() {
        let registry = PasswordManagerProviderRegistry { [("bw", "Bitwarden"), ("pp", "Proton Pass")] }
        #expect(registry.providers.map(\.title) == [String(localized: "Ombre Passwords"), "Bitwarden", "Proton Pass"])

        let ombre = registry.descriptor(for: nil)
        #expect(ombre.id == PasswordManagerProviderDescriptor.ombreID && ombre.usesBuiltInVault && ombre
            .usesBuiltInOverlay)
        // An extension: no offer to save, no menu nor autofill from Ombre.
        let bitwarden = registry.descriptor(for: "bw")
        #expect(bitwarden.title == "Bitwarden" && bitwarden.extensionID == "bw")
        #expect(!bitwarden.usesBuiltInVault && !bitwarden.usesBuiltInOverlay)
        // No longer installed and enabled: Ombre's.
        #expect(registry.descriptor(for: "gone").id == PasswordManagerProviderDescriptor.ombreID)
    }

    /// Turned off or removed: back to Ombre, said once.
    @Test func backToOmbreWhenTheExtensionGoes() {
        let choice = Choice()
        choice.passwordManagerExtensionID = "bw"
        var said: [String] = []
        #expect(!PasswordManagerChoice.extensionGone(id: "other", name: "Other", settings: choice) { said.append($0) })
        #expect(choice.passwordManagerExtensionID == "bw" && said.isEmpty)
        #expect(PasswordManagerChoice.extensionGone(id: "bw", name: "Bitwarden", settings: choice) { said.append($0) })
        #expect(choice.passwordManagerExtensionID == nil)
        #expect(said == [String(localized: "Bitwarden is no longer available: Ombre handles your passwords again.")])
    }

    /// Offered once, while Ombre handles the passwords; its first button
    /// chooses the extension.
    @Test func theOfferChoosesTheExtension() throws {
        let defaults = try #require(UserDefaults(suiteName: "PasswordManagerChoiceTests-\(UUID().uuidString)"))
        let choice = Choice()
        #expect(PasswordManagerExtensionOffer.isDue(defaults: defaults, settings: choice))
        PasswordManagerExtensionOffer.choose("bw", settings: choice)
        #expect(choice.passwordManagerExtensionID == "bw")
        #expect(!PasswordManagerExtensionOffer.isDue(defaults: defaults, settings: choice))
        choice.passwordManagerExtensionID = nil
        choice.passwordsEnabled = false
        #expect(!PasswordManagerExtensionOffer.isDue(defaults: defaults, settings: choice))
        choice.passwordsEnabled = true
        defaults.set(true, forKey: PasswordManagerExtensionOffer.shownKey)
        #expect(!PasswordManagerExtensionOffer.isDue(defaults: defaults, settings: choice))
    }

    /// Its short name ("Bitwarden"), else its name; records from before have none.
    @Test func shortNames() throws {
        var record = ExtensionRecord(source: .file(packagePath: "/x"), name: "Bitwarden Password Manager", appName: nil)
        #expect(record.displayShortName == "Bitwarden Password Manager")
        record.shortName = "Bitwarden"
        #expect(record.displayShortName == "Bitwarden")
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json["shortName"] = nil
        let old = try JSONDecoder().decode(ExtensionRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.shortName == nil && old.displayShortName == "Bitwarden Password Manager")
    }
}
