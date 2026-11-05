import WebKit

/// Whether a response is a file to save rather than a page to show: WebKit
/// can't show it, or the server says so ("Content-Disposition: attachment"),
/// like Safari. Used by tabs and popups alike.
enum BrowserDownloadPolicy {
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
