import Foundation
import PublicSuffixList

/// Web sites as browsers see them: the registrable domain ("eTLD+1") from the
/// Public Suffix List. `mail.google.com` and `docs.google.com` are one site;
/// two `github.io` pages of different users are two sites.
enum WebSite {
    static func registrableDomain(of url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return PublicSuffixList.effectiveTLDPlusOne(host) ?? host
    }

    static func isSameSite(_ first: URL, _ second: URL) -> Bool {
        guard let firstSite = registrableDomain(of: first),
              let secondSite = registrableDomain(of: second)
        else { return false }
        return firstSite == secondSite
    }
}
