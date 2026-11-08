import Foundation
import Security

/// Whether a Safari extension's `.appex` is still the one installed: same
/// bundle id, signed by the same developer team. An app replaced at the same
/// place (even re-signed ad hoc) would otherwise inherit what was allowed.
enum SafariExtensionIdentity {
    /// The developer team that validly signed it; nil when it isn't signed,
    /// signed ad hoc, or no longer matches its signature. Reads the whole
    /// bundle: call it off the main thread.
    static func signingTeam(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let information = information as? [String: Any]
        else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Whether `team` signs the extension that was installed: the team
    /// recorded then, or, for an extension installed before teams were
    /// recorded, any team (recorded from then on).
    static func accepts(team: String?, recorded: String?) -> Bool {
        guard let team else { return false }
        return recorded.map { $0 == team } ?? true
    }
}
