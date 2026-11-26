import AppKit
import Foundation

/// With a password manager extension (Bitwarden, 1Password, Proton Pass…),
/// Ombre offers once to let it handle the passwords: chosen in Settings ›
/// Passwords › "Password manager", Ombre then stays out of its way (no
/// offer to save, no menu under the fields, no autofill). The credentials
/// saved in Ombre stay. Offered when it is installed, or, for one installed
/// before, the first time Ombre would offer to save or show its menu.
@MainActor
enum PasswordManagerExtensionOffer {
    /// Its first version only turned off the offers to save: offered again.
    static let shownKey = "passwords.extensionOfferShown.v2"

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

    /// Whether it still has to be offered (once, while Ombre handles the passwords).
    static func isDue(
        defaults: UserDefaults = .standard,
        settings: PasswordManagerChoiceSettings = SettingsStore.shared
    ) -> Bool {
        !defaults.bool(forKey: shownKey) && settings.passwordsEnabled && settings.passwordManagerExtensionID == nil
    }

    /// On screen now: nothing of Ombre's comes meanwhile.
    private(set) static var isPresenting = false

    /// Before Ombre offers to save or shows its menu: a password manager
    /// extension installed earlier gets the offer, once, here. `next` runs
    /// at once when it isn't offered; after the offer only if `resumes`
    /// and Ombre still handles the passwords (a menu waits for the next
    /// focus instead: its field may be gone).
    static func beforeOmbreOffers(
        on window: NSWindow?,
        resumes: Bool,
        settings: PasswordManagerChoiceSettings = SettingsStore.shared,
        next: @escaping @MainActor () -> Void
    ) {
        guard !isPresenting else { return }
        guard let found = WebExtensionsHub.passwordManagerExtensions.first, isDue() else { return next() }
        offer(id: found.id, name: found.name, on: window) { ombreStill in
            if resumes, ombreStill, settings.passwordManagerExtensionID == nil { next() }
        }
    }

    /// Offers `name`'s extension (its short name), on `window`; `then` once
    /// answered, with whether Ombre still handles the passwords.
    static func offer(
        id: String,
        name: String,
        on window: NSWindow?,
        defaults: UserDefaults = .standard,
        settings: PasswordManagerChoiceSettings = SettingsStore.shared,
        then: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard isDue(defaults: defaults, settings: settings), !TestHost.isActive, !isPresenting else {
            return then(settings.passwordManagerExtensionID == nil)
        }
        defaults.set(true, forKey: shownKey)
        isPresenting = true
        let alert = NSAlert()
        alert.messageText = String(localized: "\(name) can save your passwords")
        alert.informativeText = String(
            localized: "passwords.extensionOffer.message",
            defaultValue: """
            Ombre can let \(name) fill in and save your passwords: Ombre then no longer offers to save them \
            nor shows its menu under the fields. The passwords saved in Ombre stay in Settings › Passwords, \
            where you can change this.
            """
        )
        alert.addButton(withTitle: String(localized: "Use \(name)"))
        alert.addButton(withTitle: String(localized: "Keep Ombre’s Passwords"))
        alert.addButton(withTitle: String(localized: "Password Settings…"))
        let answer = { (response: NSApplication.ModalResponse) in
            isPresenting = false
            switch response {
            case .alertFirstButtonReturn:
                choose(id, settings: settings)
                then(false)
            case .alertThirdButtonReturn:
                SettingsWindow.show(.passwords)
                then(settings.passwordManagerExtensionID == nil)
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

    /// The extension handles the passwords (Settings › Passwords › "Password manager").
    static func choose(_ id: String, settings: PasswordManagerChoiceSettings = SettingsStore.shared) {
        settings.passwordManagerExtensionID = id
    }
}
