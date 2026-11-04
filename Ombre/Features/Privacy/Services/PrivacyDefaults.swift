import Foundation

/// How much a space is protected, chosen in the first-launch assistant.
/// Private windows always get the fingerprinting protection, like Safari.
enum ProtectionLevel: String, CaseIterable, Identifiable {
    /// Ads and trackers blocked; fingerprinting protection in private windows only.
    case standard
    /// Standard, plus fingerprinting protection in every window.
    case strict
    /// Nothing blocked.
    case off

    var id: String {
        rawValue
    }

    /// Changes only what the level is about: the space's own lists, cookie
    /// policy and exempt sites stay.
    func apply(to settings: inout SpacePrivacySettings) {
        switch self {
        case .standard:
            settings.turnOnRecommendedProtections()
            settings.blockFingerprinting = false
        case .strict:
            settings.turnOnRecommendedProtections()
            settings.blockFingerprinting = true
        case .off:
            settings.blockThirdPartyTrackers = false
            settings.adBlock.enabled = false
            settings.blockFingerprinting = false
        }
    }
}

/// The protection level of new spaces: Standard until the assistant sets it.
@MainActor
enum PrivacyDefaults {
    static let newSpaceLevelKey = "privacy.newSpaceLevel"

    static var newSpaceLevel: ProtectionLevel {
        get {
            UserDefaults.standard.string(forKey: newSpaceLevelKey).flatMap(ProtectionLevel.init) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: newSpaceLevelKey) }
    }

    /// A new space: the current level.
    static func applyToNewSpace(_ containerID: UUID) {
        apply(newSpaceLevel, to: [containerID])
    }

    static func apply(_ level: ProtectionLevel, to containerIDs: [UUID]) {
        let store = SettingsStore.shared
        for containerID in containerIDs {
            var settings = store.privacySettings(for: containerID)
            level.apply(to: &settings)
            store.setPrivacySettings(settings, for: containerID)
            // Downloads the lists if needed, then reloads the space's pages.
            Task {
                await AdBlockService.shared.refreshSpace(containerId: containerID, reason: .settingsChanged)
            }
        }
    }
}
