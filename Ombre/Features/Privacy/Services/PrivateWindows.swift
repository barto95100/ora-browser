import Foundation

/// The open private windows. A closing one takes its site permissions with
/// it; the last one also the private tabs' icons, like Safari forgets them.
@MainActor
final class PrivateWindows {
    static let shared = PrivateWindows()
    /// Posted when the last private window has closed.
    static let lastWindowDidClose = Notification.Name("PrivateWindows.lastWindowDidClose")

    private var openWindows: Set<ObjectIdentifier> = []
    private let permissions: SitePermissionStore
    private let forgetIcons: () -> Void

    init(
        permissions: SitePermissionStore = .shared,
        forgetIcons: @escaping () -> Void = {
            Task { @MainActor in
                // Unless a new private window opened meanwhile.
                guard PrivateWindows.shared.isEmpty else { return }
                FaviconStore.shared.forgetPrivateIcons()
            }
        }
    ) {
        self.permissions = permissions
        self.forgetIcons = forgetIcons
    }

    var isEmpty: Bool {
        openWindows.isEmpty
    }

    func opened(_ window: AnyObject) {
        openWindows.insert(ObjectIdentifier(window))
    }

    /// `spaceIDs`: the spaces of the window, which exist only in it.
    func closed(_ window: AnyObject, spaceIDs: [UUID]) {
        guard openWindows.remove(ObjectIdentifier(window)) != nil else { return }
        permissions.forgetPrivatePermissions(in: spaceIDs)
        if openWindows.isEmpty {
            forgetIcons()
            NotificationCenter.default.post(name: Self.lastWindowDidClose, object: self)
        }
    }
}
