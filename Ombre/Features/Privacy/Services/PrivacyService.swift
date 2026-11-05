import Foundation

enum CookiesPolicy: String, CaseIterable, Identifiable, Codable {
    case allowAll = "Allow all"
    case blockThirdParty = "Block third-party"
    case blockAll = "Block all"
    var id: String {
        rawValue
    }
}

class PrivacyService {
    @MainActor static func clearAllWebsiteData(for containerId: UUID) async {
        await withCheckedContinuation { continuation in
            BrowserEngine.shared
                .makeProfile(identifier: containerId, isPrivate: false)
                .clearData(ofTypes: [.all]) {
                    continuation.resume()
                }
        }
    }

    private static func profile(for container: TabContainer) -> BrowserEngineProfile {
        BrowserEngine.shared.makeProfile(identifier: container.id, isPrivate: false)
    }

    private static func clearData(
        _ container: TabContainer,
        _ types: Set<BrowserWebsiteDataType>,
        host: String? = nil,
        _ completion: (() -> Void)?
    ) {
        profile(for: container).clearData(ofTypes: types, forHost: host, completion: completion)
    }

    static func clearCookies(_ container: TabContainer, completion: (() -> Void)? = nil) {
        self.clearData(
            container,
            [.cookies],
            completion
        )
    }

    static func clearCache(_ container: TabContainer, completion: (() -> Void)? = nil) {
        self.clearData(
            container,
            [.cache],
            completion
        )
    }

    /// A tab's website: in the tab's own store (its private window's
    /// session in private), or its space's when the tab isn't loaded.
    static func clearCookiesForHost(for host: String, tab: Tab, completion: (() -> Void)? = nil) {
        clearSite(host, [.cookies], tab: tab, completion)
    }

    static func clearCacheForHost(for host: String, tab: Tab, completion: (() -> Void)? = nil) {
        clearSite(host, [.cache], tab: tab, completion)
    }

    private static func clearSite(
        _ host: String,
        _ types: Set<BrowserWebsiteDataType>,
        tab: Tab,
        _ completion: (() -> Void)?
    ) {
        if let page = tab.browserPage {
            page.clearWebsiteData(ofTypes: types, forHost: host, completion: completion)
        } else {
            // The same store its page would use: the space's, or its private
            // window's session.
            BrowserEngine.shared.makeProfile(
                identifier: tab.container.id,
                isPrivate: tab.isPrivate,
                privateSession: tab.tabManager?.privateSessionID
            )
            .clearData(ofTypes: types, forHost: host, completion: completion)
        }
    }
}
