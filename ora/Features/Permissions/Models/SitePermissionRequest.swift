import Foundation

/// A permission request from a page, waiting for the user's answer.
///
/// WebKit keeps the page's request pending until it gets a decision, so the
/// request is resolved exactly once: by the user, or with a denial when it is
/// dropped unanswered (another request replaces it, the page navigates away,
/// the tab is closed).
final class SitePermissionRequest: Identifiable, Equatable {
    let id = UUID()
    let origin: SiteOrigin
    let types: Set<SitePermissionType>
    private var completion: ((Bool) -> Void)?

    init(origin: SiteOrigin, types: Set<SitePermissionType>, completion: @escaping (Bool) -> Void) {
        self.origin = origin
        self.types = types
        self.completion = completion
    }

    deinit {
        resolve(granted: false)
    }

    func resolve(granted: Bool) {
        guard let completion else { return }
        self.completion = nil
        completion(granted)
    }

    static func == (lhs: SitePermissionRequest, rhs: SitePermissionRequest) -> Bool {
        lhs.id == rhs.id
    }
}
