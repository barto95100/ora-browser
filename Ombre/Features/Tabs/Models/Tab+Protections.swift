import Foundation

/// The shield of the address bar: what content rules keep from the page, and
/// sites exempted from them (in this tab's space).
extension Tab {
    /// The site protections are set for: its registrable domain.
    var protectionSite: String? {
        WebSite.registrableDomain(of: url)
    }

    var blockedContentCount: Int {
        blockedContent.values.reduce(0, +)
    }

    var privacySettings: SpacePrivacySettings {
        SettingsStore.shared.privacySettings(for: container.id)
    }

    func areProtectionsEnabled(for url: URL) -> Bool {
        guard let site = WebSite.registrableDomain(of: url) else { return true }
        return !privacySettings.exemptSites.contains(site)
    }

    var areProtectionsEnabled: Bool {
        areProtectionsEnabled(for: url)
    }

    /// Turns protections on or off for the current site, then reloads it.
    func setProtections(enabled: Bool) {
        guard let site = protectionSite else { return }
        var settings = privacySettings
        settings.exemptSites.removeAll { $0 == site }
        if !enabled {
            settings.exemptSites.append(site)
        }
        SettingsStore.shared.setPrivacySettings(settings, for: container.id)
        browserPage?.setContentBlocking(enabled: enabled)
        blockedContent = [:]
        browserPage?.reload()
    }

    func recordBlockedContent(from url: URL) {
        blockedContent[url.host ?? url.absoluteString, default: 0] += 1
    }
}
