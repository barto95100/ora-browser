import Foundation

/// A download as the download permission sees it (`BrowserDownloadTask`).
@MainActor
protocol PermissionGatedDownload: AnyObject {
    var isRequestedByUser: Bool { get }
    var onDestinationRequest: ((URLResponse, String, @escaping @MainActor @Sendable (URL?) -> Void) -> Void)? {
        get set
    }
    func cancel()
}

extension BrowserDownloadTask: PermissionGatedDownload {}

/// Whether a site may download files, like Safari ("Allow downloads on…"):
/// the site's choice in its space, else asked the first time. The download
/// waits for the answer (WebKit's question of where to save it is held), and
/// is cancelled if refused.
@MainActor
enum DownloadPermission {
    /// `site`: the page that started it. `start` hands the download on (to
    /// the download manager); `done` runs once decided, either way.
    static func check(
        _ download: PermissionGatedDownload,
        site: URL?,
        spaceID: UUID,
        isPrivate: Bool,
        present: (SitePermissionRequest) -> Void,
        start: @escaping () -> Void,
        done: @escaping () -> Void = {}
    ) {
        // Asked for in the menu, or from no site (a local file): not the
        // site's doing.
        guard !download.isRequestedByUser, let origin = site.flatMap(SiteOrigin.init(url:)) else {
            start()
            done()
            return
        }
        switch SitePermissionStore.shared.permissions(for: origin, in: spaceID, isPrivate: isPrivate).downloads {
        case .allow:
            start()
            done()
        case .deny:
            download.cancel()
            done()
        case .ask:
            // WebKit asks where to save it meanwhile: the question is kept
            // for the answer.
            var heldQuestion: (URLResponse, String, @MainActor @Sendable (URL?) -> Void)?
            download.onDestinationRequest = { response, filename, completion in
                heldQuestion = (response, filename, completion)
            }
            present(SitePermissionRequest(origin: origin, types: [.downloads]) { granted in
                MainActor.assumeIsolated {
                    if granted {
                        start()
                        if let (response, filename, completion) = heldQuestion {
                            if let ask = download.onDestinationRequest {
                                ask(response, filename, completion)
                            } else {
                                completion(nil)
                            }
                        }
                    } else {
                        heldQuestion?.2(nil)
                        download.cancel()
                    }
                    heldQuestion = nil
                    done()
                }
            })
        }
    }
}
