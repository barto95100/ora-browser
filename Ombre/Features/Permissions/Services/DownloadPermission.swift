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
/// the site's choice in its space, else the general choice of Settings (asked
/// the first time by default). The download waits for the answer (WebKit's
/// question of where to save it is held), and is cancelled if refused.
@MainActor
enum DownloadPermission {
    /// `site`: the page that started it. `start` hands the download on (to
    /// the download manager); `done` runs once decided, either way.
    /// `allowsByDefault`: for a site without a choice (Settings).
    static func check(
        _ download: PermissionGatedDownload,
        site: URL?,
        spaceID: UUID,
        isPrivate: Bool,
        allowsByDefault: Bool = SettingsStore.shared.allowsDownloadsByDefault,
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
        let saved = SitePermissionStore.shared.permissions(for: origin, in: spaceID, isPrivate: isPrivate)
        switch saved.downloadsChoice ?? (allowsByDefault ? .allow : .ask) {
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
            let decide: (Bool) -> Void = { granted in
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
                    // A question WebKit asks later gets "no" at once.
                    download.onDestinationRequest = nil
                    download.cancel()
                }
                heldQuestion = nil
                done()
            }
            // The site asks again while asked (two files): one question for both.
            let key = PendingKey(origin: origin, spaceID: spaceID, isPrivate: isPrivate)
            if pending[key] != nil {
                pending[key]?.append(decide)
                return
            }
            pending[key] = [decide]
            present(SitePermissionRequest(origin: origin, types: [.downloads]) { granted in
                MainActor.assumeIsolated {
                    let waiting = pending.removeValue(forKey: key) ?? []
                    waiting.forEach { $0(granted) }
                }
            })
        }
    }

    /// The site a download is asked for: the page shown, else the page
    /// whose link opened the tab, Peek or popup only for the file (the user
    /// clicked there; the file's server is often a file host), else the file.
    /// Only addresses of a site count: a blank or local page (`about:blank`
    /// written by a script, a file) never lets a download through unasked.
    nonisolated static func site(shown: URL?, opener: URL?, file: URL?) -> URL? {
        [shown, opener].lazy.compactMap { $0 }.first { SiteOrigin(url: $0) != nil } ?? file
    }

    private struct PendingKey: Hashable {
        let origin: SiteOrigin
        let spaceID: UUID
        let isPrivate: Bool
    }

    /// The downloads waiting for the question asked for their site.
    private static var pending: [PendingKey: [(Bool) -> Void]] = [:]
}
