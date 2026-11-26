import Foundation

/// Who handles the passwords: Ombre, or a password manager extension that
/// is installed and enabled (Settings › Passwords › "Password manager").
///
/// With an extension, Ombre stays out of its way: no offer to save, no menu
/// under the fields, no autofill nor auto-submit. The credentials saved in
/// Ombre stay, listed in the settings.
struct PasswordManagerProviderDescriptor: Identifiable, Hashable {
    /// Ombre's own choice.
    static let ombreID = "ombre"

    /// `ombreID`, or the extension's id.
    let id: String
    let title: String
    let summary: String
    /// The extension chosen, if not Ombre.
    let extensionID: String?

    var usesBuiltInVault: Bool {
        extensionID == nil
    }

    var usesBuiltInOverlay: Bool {
        extensionID == nil
    }

    static var ombre: PasswordManagerProviderDescriptor {
        PasswordManagerProviderDescriptor(
            id: ombreID,
            title: String(localized: "Ombre Passwords"),
            summary: String(localized: "Store encrypted credentials in Ombre and show Ombre's autofill overlay."),
            extensionID: nil
        )
    }

    /// `name`: its short name ("Bitwarden").
    static func forExtension(id: String, name: String) -> PasswordManagerProviderDescriptor {
        PasswordManagerProviderDescriptor(
            id: id,
            title: name,
            summary: String(localized: "\(name) fills in and saves your passwords: Ombre stays out of its way."),
            extensionID: id
        )
    }
}

@MainActor
final class PasswordManagerProviderRegistry {
    static let shared = PasswordManagerProviderRegistry()

    /// The password manager extensions installed and enabled: id and short name.
    private let extensions: () -> [(id: String, name: String)]

    init(extensions: @escaping () -> [(id: String, name: String)] = { WebExtensionsHub.passwordManagerExtensions }) {
        self.extensions = extensions
    }

    /// Ombre, then each password manager extension.
    var providers: [PasswordManagerProviderDescriptor] {
        [.ombre] + extensions().map { .forExtension(id: $0.id, name: $0.name) }
    }

    /// The choice saved (`SettingsStore.passwordManagerExtensionID`): Ombre
    /// when it is nil, or the extension is no longer there and enabled.
    func descriptor(for extensionID: String?) -> PasswordManagerProviderDescriptor {
        guard let extensionID, let found = extensions().first(where: { $0.id == extensionID }) else { return .ombre }
        return .forExtension(id: found.id, name: found.name)
    }
}

/// Where the choice is (`SettingsStore`; another in tests).
@MainActor
protocol PasswordManagerChoiceSettings: AnyObject {
    var passwordsEnabled: Bool { get }
    var passwordManagerExtensionID: String? { get set }
}

extension SettingsStore: PasswordManagerChoiceSettings {}

/// The extension chosen is turned off or removed: back to Ombre's passwords, said.
@MainActor
enum PasswordManagerChoice {
    /// Whether the choice went back to Ombre.
    @discardableResult
    static func extensionGone(
        id: String,
        name: String,
        settings: PasswordManagerChoiceSettings = SettingsStore.shared,
        notify: (String) -> Void = { ToastManager.shared.show($0, type: .info, icon: .system("key.fill")) }
    ) -> Bool {
        guard settings.passwordManagerExtensionID == id else { return false }
        settings.passwordManagerExtensionID = nil
        notify(String(localized: "\(name) is no longer available: Ombre handles your passwords again."))
        return true
    }
}
