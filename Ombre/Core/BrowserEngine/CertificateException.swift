import CryptoKit
import Foundation
import Security

/// "Continue anyway" on a site whose certificate isn't trusted: allowed for
/// that certificate only (its SHA-256), never for whatever the host presents
/// later, which could be someone else's on the network (MOT-12).
enum CertificateException {
    /// SHA-256 of the server's own certificate (the chain's first), in hex.
    static func digest(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return nil }
        return digest(of: leaf)
    }

    static func digest(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// The certificate WebKit refused, from the error of a failed load.
    static func trust(in error: Error) -> SecTrust? {
        let value = (error as NSError).userInfo[NSURLErrorFailingURLPeerTrustErrorKey]
        guard let value, CFGetTypeID(value as CFTypeRef) == SecTrustGetTypeID() else { return nil }
        return (value as! SecTrust) // swiftlint:disable:this force_cast
    }

    /// Every certificate accepted since launch, in any page: a page showing
    /// one says "Not Secure", even one that didn't accept it itself (a
    /// popup reusing the connection of the tab that did). Only for what the
    /// address shows: which certificate a page trusts stays its own.
    @MainActor private static var acceptedDigests: Set<String> = []

    @MainActor static func remember(_ digest: String) {
        acceptedDigests.insert(digest)
    }

    #if DEBUG
        /// For the tests: leaves nothing behind.
        @MainActor static func forget(_ digest: String) {
            acceptedDigests.remove(digest)
        }
    #endif

    /// Whether the certificate of `trust` was accepted by the user rather
    /// than trusted by macOS.
    @MainActor static func wasAccepted(_ trust: SecTrust?) -> Bool {
        guard !acceptedDigests.isEmpty, let trust, let digest = digest(of: trust) else { return false }
        return acceptedDigests.contains(digest)
    }

    /// Whether a server presenting `digest` for `host` was accepted.
    static func isAccepted(digest: String?, host: String, exceptions: [String: String]) -> Bool {
        guard let digest, let accepted = exceptions[host] else { return false }
        return accepted == digest
    }
}
