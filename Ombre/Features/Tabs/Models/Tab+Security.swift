import Foundation

/// The lock, or "Not Secure", in the tab's address bar: what the page
/// really loaded (mixed content, a certificate accepted with "Continue
/// Anyway"), like Safari and the popups.
@MainActor
extension Tab {
    /// The page's, or what the address says for a tab without a page.
    var security: PageSecurity {
        runtime?.pageSecurity ?? PageSecurity.of(url, hasOnlySecureContent: true)
    }

    /// Reads the page's security again (new address, certificate, or
    /// insecure content loaded).
    func updateSecurity() {
        guard let page = browserPage, let runtime else { return }
        let security = page.security
        if runtime.pageSecurity != security { runtime.pageSecurity = security }
    }
}
