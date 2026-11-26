import Combine
import Foundation

/// Where "Prompt to save passwords" is (`SettingsStore`; another in tests).
@MainActor
protocol PasswordSavingSetting: AnyObject {
    var passwordSavePromptsEnabled: Bool { get set }
}

extension SettingsStore: PasswordSavingSetting {}

/// `chrome.privacy` for extensions (`ExtensionComplements`).
///
/// `services.passwordSavingEnabled` is Ombre's own setting, Settings ›
/// Passwords › "Prompt to save passwords": an extension that turns it off
/// (a password manager) really stops Ombre's offers, and the setting says
/// which one did. The user changing it ends the extension's hold, as in
/// Chrome. What Ombre can't change (WebRTC, prefetching…) is
/// "not_controllable": read, never set.
@MainActor
final class ExtensionPrivacy: ObservableObject {
    static let shared = ExtensionPrivacy()

    /// The extension holding "Prompt to save passwords", if one does.
    @Published private(set) var passwordSavingController: String?
    /// Its name, for the setting ("Turned off by Bitwarden").
    @Published private(set) var passwordSavingControllerName: String?

    private let settings: PasswordSavingSetting
    private let defaults: UserDefaults
    private let key: String

    private struct Hold: Codable {
        let id: String
        let name: String?
        /// The setting before the extension changed it: back to it when it lets go.
        let previous: Bool
    }

    init(
        settings: PasswordSavingSetting = SettingsStore.shared,
        defaults: UserDefaults = .standard,
        key: String = "extensions.privacy.passwordSaving"
    ) {
        self.settings = settings
        self.defaults = defaults
        self.key = key
        if let hold = self.hold {
            passwordSavingController = hold.id
            passwordSavingControllerName = hold.name
        }
    }

    private var hold: Hold? {
        get { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Hold.self, from: $0) } }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
            passwordSavingController = newValue?.id
            passwordSavingControllerName = newValue?.name
        }
    }

    /// Settings Ombre can't change, with what it does.
    static let fixedValues: [String: Any] = [
        "network.networkPredictionEnabled": true,
        "network.webRTCIPHandlingPolicy": "default_public_interface_only",
        "services.alternateErrorPagesEnabled": false,
        "services.autofillEnabled": false,
        // Ombre fills in no addresses or cards: nothing to turn off.
        "services.autofillAddressEnabled": false,
        "services.autofillCreditCardEnabled": false,
        "services.safeBrowsingEnabled": false,
        "services.safeBrowsingExtendedReportingEnabled": false,
        "services.searchSuggestEnabled": true,
        "services.spellingServiceEnabled": false,
        "services.translationServiceEnabled": true,
        "websites.doNotTrackEnabled": false,
        "websites.hyperlinkAuditingEnabled": true,
        "websites.protectedContentEnabled": true,
        "websites.referrersEnabled": true,
        "websites.thirdPartyCookiesAllowed": false,
        "websites.topicsEnabled": false,
        "websites.fledgeEnabled": false,
        "websites.adMeasurementEnabled": false
    ]

    /// Turned off already, so "set to off" is accepted (a password manager
    /// turns them all off with the passwords): nothing changes.
    static let offAlready: Set<String> = ["services.autofillAddressEnabled", "services.autofillCreditCardEnabled"]

    func handle(
        _ method: String,
        _ details: [String: Any],
        extensionID: String,
        extensionName: String?
    ) throws -> Any? {
        guard let setting = details["setting"] as? String else {
            throw ExtensionComplementFailure.invalid("Invalid setting.") // not shown
        }
        let options = details["details"] as? [String: Any] ?? [:]
        if let scope = options["scope"] as? String, scope != "regular" {
            throw ExtensionComplementFailure.invalid("Only the \"regular\" scope is supported.") // not shown
        }
        if setting == "services.passwordSavingEnabled" {
            return try passwordSaving(method, options, extensionID: extensionID, extensionName: extensionName)
        }
        guard let value = Self.fixedValues[setting] else {
            throw ExtensionComplementFailure.unknownCall("privacy.\(setting)")
        }
        switch method {
        case "get":
            let control = Self.offAlready.contains(setting) ? "controllable_by_this_extension" : "not_controllable"
            return ["value": value, "levelOfControl": control]
        case "set":
            if Self.offAlready.contains(setting), options["value"] as? Bool == false { return nil }
            throw ExtensionComplementFailure.invalid("Ombre can't change this setting.") // not shown
        case "clear":
            return nil
        default:
            throw ExtensionComplementFailure.unknownCall("privacy.\(setting).\(method)")
        }
    }

    private func passwordSaving(
        _ method: String,
        _ options: [String: Any],
        extensionID: String,
        extensionName: String?
    ) throws -> Any? {
        switch method {
        case "get":
            let control = switch passwordSavingController {
            case nil: "controllable_by_this_extension"
            case extensionID: "controlled_by_this_extension"
            default: "controlled_by_other_extensions"
            }
            return ["value": settings.passwordSavePromptsEnabled, "levelOfControl": control]
        case "set":
            guard let value = options["value"] as? Bool else {
                throw ExtensionComplementFailure.invalid("The value must be a boolean.") // not shown
            }
            let previous = hold?.previous ?? settings.passwordSavePromptsEnabled
            hold = Hold(id: extensionID, name: extensionName, previous: previous)
            settings.passwordSavePromptsEnabled = value
            return nil
        case "clear":
            release(extensionID: extensionID)
            return nil
        default:
            throw ExtensionComplementFailure.unknownCall("privacy.services.passwordSavingEnabled.\(method)")
        }
    }

    /// The extension lets go (or is removed): the setting as it was before.
    func release(extensionID: String) {
        guard let hold, hold.id == extensionID else { return }
        self.hold = nil
        settings.passwordSavePromptsEnabled = hold.previous
    }

    /// The user changed the setting: it is theirs again.
    func userChangedPasswordSaving() {
        hold = nil
    }
}
