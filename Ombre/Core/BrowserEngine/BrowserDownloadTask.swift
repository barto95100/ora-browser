import Foundation
@preconcurrency import WebKit

@MainActor
final class BrowserDownloadTask: NSObject, WKDownloadDelegate {
    let id = UUID()
    var originalURL: URL
    var onDestinationRequest: ((URLResponse, String, @escaping @MainActor @Sendable (URL?) -> Void) -> Void)?
    var onRedirect: ((URL) -> Void)?
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    private let download: WKDownload

    init(download: WKDownload, originalURL: URL) {
        self.download = download
        self.originalURL = originalURL
        super.init()
        self.download.delegate = self
    }

    var progress: Progress {
        download.progress
    }

    func cancel() {
        download.cancel()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        if let onDestinationRequest {
            onDestinationRequest(response, suggestedFilename, completionHandler)
        } else {
            completionHandler(nil)
        }
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
    ) {
        if let url = newRequest.url {
            originalURL = url
            onRedirect?(url)
        }
        decisionHandler(.allow)
    }

    func downloadDidFinish(_ download: WKDownload) {
        onFinish?()
    }

    func download(_ download: WKDownload, didFailWithError error: Error) {
        onFail?(error)
    }
}
