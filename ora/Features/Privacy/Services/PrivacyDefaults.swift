import Foundation

/// Ads and trackers are blocked by default in new spaces. Spaces created
/// before get the choice once, at launch.
@MainActor
enum PrivacyDefaults {
    private static let offeredKey = "privacy.recommendedProtections.offered"

    /// A new space: recommended protections on.
    static func applyToNewSpace(_ containerID: UUID) {
        turnOn(in: [containerID])
        // A space created after the offer needs no offer.
        UserDefaults.standard.set(true, forKey: offeredKey)
    }

    /// Once: offers to turn the recommended protections on in the spaces
    /// that block neither ads nor trackers.
    static func offerIfNeeded(containerIDs: [UUID], dialogManager: DialogManager) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return }
        defaults.set(true, forKey: offeredKey)

        let unprotected = containerIDs.filter { !SettingsStore.shared.privacySettings(for: $0).hasProtections }
        guard !unprotected.isEmpty else { return }

        dialogManager.confirm(
            title: "Block ads and trackers?",
            message: "Ora can block ads and trackers in your spaces with AdGuard's lists. "
                + "You can turn them off for a site from the shield in the address bar, "
                + "or for a space in Settings › Spaces.",
            confirmLabel: "Turn On",
            onConfirm: { turnOn(in: unprotected) }
        )
    }

    private static func turnOn(in containerIDs: [UUID]) {
        let store = SettingsStore.shared
        for containerID in containerIDs {
            var settings = store.privacySettings(for: containerID)
            settings.turnOnRecommendedProtections()
            store.setPrivacySettings(settings, for: containerID)
            // Downloads the lists if needed, then reloads the space's pages.
            Task {
                await AdBlockService.shared.refreshSpace(containerId: containerID, reason: .settingsChanged)
            }
        }
    }
}
