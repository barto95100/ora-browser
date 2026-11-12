import Foundation

/// How safe the connection of a page is, for its address (a tab's, Peek's
/// or a popup's).
enum PageSecurity: Equatable {
    /// HTTPS with a trusted certificate, and everything it loaded too.
    case secure
    /// HTTP, an HTTPS page that loaded something over HTTP, or one whose
    /// certificate was accepted with "Continue Anyway" (like Safari).
    case notSecure
    /// No connection of its own (`about:blank`, `blob:`, `data:`, a file).
    case local

    static func of(
        _ url: URL?,
        hasOnlySecureContent: Bool,
        usesAcceptedCertificate: Bool = false
    ) -> PageSecurity {
        switch url?.scheme?.lowercased() {
        case "https": hasOnlySecureContent && !usesAcceptedCertificate ? .secure : .notSecure
        case "http": .notSecure
        default: .local
        }
    }
}
