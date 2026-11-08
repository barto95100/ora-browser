import WebKit

/// Whether a response is a file to save rather than a page to show: WebKit
/// can't show it, or the server says so ("Content-Disposition: attachment"),
/// like Safari. Used by tabs and popups alike.
enum BrowserDownloadPolicy {
    enum Handling: Equatable {
        /// Shown in its frame.
        case show
        /// A frame's file: saved, the page's own load and address untouched.
        case frameDownload
        /// The page's own load becomes a download: the page shown stays.
        case pageDownload
    }

    static func handling(isForMainFrame: Bool, isDownload: Bool) -> Handling {
        guard isDownload else { return .show }
        return isForMainFrame ? .pageDownload : .frameDownload
    }

    @MainActor
    static func isDownload(_ response: WKNavigationResponse) -> Bool {
        isDownload(canShowMIMEType: response.canShowMIMEType, response: response.response)
    }

    static func isDownload(canShowMIMEType: Bool, response: URLResponse) -> Bool {
        let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let isAttachment = disposition?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment")
            ?? false
        return !canShowMIMEType || isAttachment
    }
}
