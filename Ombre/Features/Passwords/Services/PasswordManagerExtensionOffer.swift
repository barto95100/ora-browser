import AppKit
import Foundation

/// With a password manager extension (Bitwarden, 1Password, Proton Pass…),
/// Ombre offers once to stop its own "save this password?" offers, which
/// would come with the extension's. Settings › Passwords › "Prompt to save
/// passwords" is the setting, whatever is chosen here; an extension may
/// also change it itself (`ExtensionPrivacy`).
@MainActor
enum PasswordManagerExtensionOffer {
    static let shownKey = "passwords.extensionOfferShown"

    /// Names of the password managers Ombre knows, as their extensions call themselves.
    private static let names = [
        "bitwarden", "1password", "proton pass", "dashlane", "lastpass", "nordpass", "keeper password", // not shown
        "keeper®", "roboform", // not shown
        "enpass", "keepassxc", "icloud passwords", "mots de passe icloud", "zoho vault", "sticky password" // not shown
    ]

    static func isPasswordManager(_ name: String) -> Bool {
        let name = name.lowercased()
        return names.contains { name.contains($0) }
    }

    /// Whether it still has to be offered (once, while Ombre offers to save).
    static func isDue(defaults: UserDefaults = .standard, settings: SettingsStore = .shared) -> Bool {
        // Only while Ombre itself offers to save (its passwords on, its own vault).
        !defaults.bool(forKey: shownKey) && settings.passwordsEnabled && settings.passwordSavePromptsEnabled
            && PasswordManagerProviderRegistry.shared.descriptor(for: settings.passwordManagerProvider).usesBuiltInVault
    }

    /// Before Ombre offers to save: a password manager extension installed
    /// earlier gets the offer, once, here; then `present` if Ombre still offers.
    static func beforeSavePrompt(on window: NSWindow?, present: @escaping @MainActor () -> Void) {
        guard let name = WebExtensionsHub.enabledPasswordManagerName, isDue() else { return present() }
        offer(for: name, on: window) { stillOffers in
            if stillOffers { present() }
        }
    }

    /// Offers it for `name`'s extension, on `window`; `then` once answered
    /// (with whether Ombre still offers to save).
    static func offer(
        for name: String,
        on window: NSWindow?,
        defaults: UserDefaults = .standard,
        settings: SettingsStore = .shared,
        then: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard isDue(defaults: defaults, settings: settings), !TestHost.isActive else { return then(true) }
        defaults.set(true, forKey: shownKey)
        let alert = NSAlert()
        alert.messageText = String(localized: "\(name) can save your passwords")
        alert.informativeText = String(
            localized: "Ombre can stop offering to save passwords, so they stay in \(name). You can change this in Settings › Passwords."
        )
        alert.addButton(withTitle: String(localized: "Stop Offering"))
        alert.addButton(withTitle: String(localized: "Keep Offering"))
        alert.addButton(withTitle: String(localized: "Password Settings…"))
        let answer = { (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                settings.passwordSavePromptsEnabled = false
                ExtensionPrivacy.shared.userChangedPasswordSaving()
                then(false)
            case .alertThirdButtonReturn:
                SettingsWindow.show(.passwords)
                then(settings.passwordSavePromptsEnabled)
            default:
                then(true)
            }
        }
        if let window {
            alert.beginSheetModal(for: window) { answer($0) }
        } else {
            answer(alert.runModal())
        }
    }
}
