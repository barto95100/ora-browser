import Foundation
import os
@preconcurrency import WebKit

private let logger = Logger(category: "BrowserEngine")

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

    /// A deleted space's profile: forgotten, and its website data store
    /// removed from the disk (unless a page still uses it: logged).
    @MainActor
    func removeProfile(identifier: UUID) async {
        profileCacheLock.lock()
        profileCache[ProfileKey(identifier: identifier, isPrivate: false)] = nil
        profileCacheLock.unlock()
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        } catch {
            logger.error("Removing a space's data store failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether the profile of a space is kept, for the tests.
    func hasCachedProfile(identifier: UUID) -> Bool {
        profileCacheLock.lock()
        defer { profileCacheLock.unlock() }
        return profileCache[ProfileKey(identifier: identifier, isPrivate: false)] != nil
    }

    func makePage(
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration,
        delegate: BrowserPageDelegate?
    ) -> BrowserPage {
        BrowserPage(profile: profile, configuration: configuration, delegate: delegate)
    }
}
