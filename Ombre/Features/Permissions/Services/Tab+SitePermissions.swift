import Foundation

extension Tab {
    /// Shows a permission prompt for this tab. A request still waiting for an
    /// answer is denied first, so only one prompt is ever visible.
    func presentPermissionRequest(_ request: SitePermissionRequest) {
        permissionRequest?.resolve(granted: false)
        permissionRequest = request
    }

    /// Answers the visible prompt and, if asked to, remembers the choice for
    /// the site in this tab's space.
    func answerPermissionRequest(granted: Bool, remember: Bool) {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        if remember {
            SitePermissionStore.shared.setState(
                granted ? .allow : .deny,
                for: request.types,
                origin: request.origin,
                in: container.id,
                isPrivate: isPrivate
            )
        }
        request.resolve(granted: granted)
    }

    /// Denies and hides the visible prompt, if any.
    func cancelPermissionRequest() {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        request.resolve(granted: false)
    }
}
