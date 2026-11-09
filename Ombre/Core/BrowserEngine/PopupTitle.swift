import Foundation
@preconcurrency import WebKit

/// The popup's title: the site the page comes from, said not private over
/// HTTP. A page without a host of its own (`about:blank` written by its
/// opener, `blob:`) shows the site it really comes from, never nothing (its
/// own title would then be all that shows).
enum PopupTitle {
    /// The origin of a frame, as an address (`https://host[:port]`).
    @MainActor static func origin(of frame: WKFrameInfo) -> URL? {
        let origin = frame.securityOrigin
        guard !origin.host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 { components.port = origin.port }
        return components.url
    }

    static func title(for url: URL?, openerURL: URL? = nil) -> String {
        guard let url else { return "" }
        let scheme = url.scheme?.lowercased() ?? ""
        if let host = url.host(), !host.isEmpty {
            return scheme == "https" ? host : String(localized: "Not Secure — \(host)")
        }
        if scheme == "blob", let inner = URL(string: String(url.absoluteString.dropFirst("blob:".count))),
           inner.host() != nil
        {
            return title(for: inner)
        }
        if scheme == "about", let openerURL, openerURL.host() != nil {
            return title(for: openerURL)
        }
        return url.absoluteString.isEmpty ? "" : (scheme.isEmpty ? url.absoluteString : "\(scheme):")
    }
}
