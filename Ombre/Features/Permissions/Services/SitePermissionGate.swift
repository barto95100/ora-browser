import Foundation

/// A site's permission (camera, microphone, notifications, position,
/// screen), decided in its space like Safari: the saved choice, else a prompt
/// shown by whoever holds the page (tab, Peek, popup).
@MainActor
enum SitePermissionGate {
    /// `present` shows `SitePermissionRequest` to the user, who answers it
    /// (see `remember`); `decisionHandler` gets the decision once.
    static func request(
        _ permission: BrowserPermissionKind,
        origin: URL?,
        spaceID: UUID,
        isPrivate: Bool,
        present: (SitePermissionRequest) -> Void,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        guard let origin = origin.flatMap(SiteOrigin.init(url:)) else {
            decisionHandler(.deny)
            return
        }
        // A site allowed to send notifications: macOS must allow Ombre too
        // (asked once, right after the user allowed the site).
        let answer: @MainActor (BrowserPermissionDecision) -> Void = switch permission {
        case .notifications: { decision in
                if decision == .grant {
                    WebNotificationCenter.shared.requestAuthorizationIfNeeded()
                }
                decisionHandler(decision)
            }
        // A site allowed to know the position: macOS must let Ombre use
        // Location Services too (WebKit never asks it).
        case .geolocation: LocationAuthorization.askingMacOS(then: decisionHandler)
        default: decisionHandler
        }

        let types = permission.sitePermissionTypes
        let saved = SitePermissionStore.shared.permissions(for: origin, in: spaceID, isPrivate: isPrivate)
        switch saved.decision(for: types) {
        case .allow:
            answer(.grant)
        case .deny:
            answer(.deny)
        case .ask:
            present(SitePermissionRequest(origin: origin, types: types) { granted in
                answer(granted ? .grant : .deny)
            })
        }
    }

    /// The answer to `navigator.permissions.query()`, without asking.
    static func query(
        _ permission: BrowserPermissionKind,
        origin: URL?,
        spaceID: UUID,
        isPrivate: Bool
    ) -> BrowserPermissionDecision {
        guard let origin = origin.flatMap(SiteOrigin.init(url:)) else { return .prompt }
        return SitePermissionStore.shared
            .permissions(for: origin, in: spaceID, isPrivate: isPrivate)
            .decision(for: permission.sitePermissionTypes)
            .permissionQueryDecision
    }

    /// The user answered a prompt: the page gets it, and the choice is kept
    /// for the site in the space if asked.
    static func answer(
        _ request: SitePermissionRequest,
        granted: Bool,
        remember: Bool,
        spaceID: UUID,
        isPrivate: Bool
    ) {
        if remember {
            SitePermissionStore.shared.setState(
                granted ? .allow : .deny,
                for: request.types,
                origin: request.origin,
                in: spaceID,
                isPrivate: isPrivate
            )
        }
        request.resolve(granted: granted)
    }
}
