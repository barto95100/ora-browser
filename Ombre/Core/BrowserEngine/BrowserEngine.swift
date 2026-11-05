import Foundation

struct BrowserPageConfiguration {
    /// Appended by WebKit to its own user agent prefix: see `SafariUserAgent`.
    let applicationNameForUserAgent: String?
    let allowsJavaScript: Bool
    let allowsJavaScriptWindowsAutomatically: Bool
    let allowsAirPlayForMediaPlayback: Bool
    let allowsBackForwardNavigationGestures: Bool
    let mediaPlaybackRequiresUserAction: Bool
    let scriptMessageNames: [String]
    let userScripts: [BrowserUserScript]
    let privacySettings: SpacePrivacySettings
    /// Gives pages the `Notification` API (not in private browsing, like Safari).
    let enablesWebNotifications: Bool

    static func ombreDefault(
        userScripts: [BrowserUserScript],
        privacySettings: SpacePrivacySettings,
        enablesWebNotifications: Bool = true
    ) -> BrowserPageConfiguration {
        BrowserPageConfiguration(
            applicationNameForUserAgent: SafariUserAgent.current,
            allowsJavaScript: true,
            allowsJavaScriptWindowsAutomatically: false,
            allowsAirPlayForMediaPlayback: true,
            allowsBackForwardNavigationGestures: true,
            mediaPlaybackRequiresUserAction: false,
            scriptMessageNames: ["linkHover", "mediaEvent", "passwordManager", "favicon"],
            userScripts: userScripts,
            privacySettings: privacySettings,
            enablesWebNotifications: enablesWebNotifications
        )
    }
}

final class BrowserEngine {
    private struct ProfileKey: Hashable {
        let identifier: UUID
        let isPrivate: Bool
    }

    static let shared = BrowserEngine()
    /// Posted when `allowsInspection` changes: open pages follow it.
    static let inspectionDidChange = Notification.Name("BrowserEngine.inspectionDidChange")

    /// Whether pages can be inspected with Safari's Web Inspector (Develop
    /// menu): the "Allow Web Inspector" setting.
    var allowsInspection = false {
        didSet {
            guard allowsInspection != oldValue else { return }
            NotificationCenter.default.post(name: Self.inspectionDidChange, object: self)
        }
    }

    /// Set at launch on macOS 15.4+ (see `WebExtensionsManager`): pages of
    /// normal windows run the enabled extensions. A `WKWebExtensionController`.
    var webExtensionController: AnyObject?
    private let profileCacheLock = NSLock()
    private var profileCache: [ProfileKey: BrowserEngineProfile] = [:]

    func makeProfile(identifier: UUID, isPrivate: Bool) -> BrowserEngineProfile {
        if isPrivate {
            return BrowserEngineProfile(identifier: identifier, isPrivate: true)
        }

        let key = ProfileKey(identifier: identifier, isPrivate: false)
        profileCacheLock.lock()
        defer { profileCacheLock.unlock() }

        if let profile = profileCache[key] {
            return profile
        }

        let profile = BrowserEngineProfile(identifier: identifier, isPrivate: false)
        profileCache[key] = profile
        return profile
    }

    func makePage(
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration,
        delegate: BrowserPageDelegate?
    ) -> BrowserPage {
        BrowserPage(profile: profile, configuration: configuration, delegate: delegate)
    }
}
