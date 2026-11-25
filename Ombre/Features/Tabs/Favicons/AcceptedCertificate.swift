import Foundation

/// The certificate the user accepted for an icon's host (Continue anyway,
/// see `CertificateException`): the only one trusted to fetch that icon.
struct AcceptedCertificate: Equatable, Sendable {
    let host: String
    /// SHA-256 of the server's certificate, in hex.
    let digest: String

    /// The exception of the page for the icon's host, if it has one: only
    /// for `https`, and only that host's.
    static func `for`(_ iconURL: URL, in exceptions: [String: String]) -> AcceptedCertificate? {
        guard iconURL.scheme?.lowercased() == "https", let host = iconURL.host,
              let digest = exceptions[host]
        else { return nil }
        return AcceptedCertificate(host: host, digest: digest)
    }

    /// Whether a server presenting `digest` for `host` is the one accepted.
    func trusts(host: String, digest: String?) -> Bool {
        CertificateException.isAccepted(digest: digest, host: host, exceptions: [self.host: self.digest])
    }
}
