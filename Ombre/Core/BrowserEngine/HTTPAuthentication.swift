import Foundation

/// A site's login asked by the server itself (HTTP Basic, Digest, NTLM): a
/// router, a NAS, an intranet (MOT-11). Like Safari: a sheet asks for the
/// name and password, says which site asks and warns when the password
/// would travel unencrypted.
struct HTTPAuthenticationRequest: Equatable {
    let host: String
    let realm: String?
    /// Over HTTPS (or another encrypted connection).
    let isSecure: Bool
    /// Times a name and password were already refused for this request.
    let previousFailureCount: Int
    /// The name tried last, filled in again.
    let proposedUser: String?
}

enum HTTPAuthentication {
    /// The methods a sheet answers; the others (certificates…) are WebKit's.
    static let methods: Set<String> = [
        NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM
    ]

    /// Asking again after this many refusals: the page gets the server's
    /// refusal instead (a script can't make the sheet loop forever).
    static let maximumAttempts = 3

    enum Decision: Equatable {
        /// WebKit's own handling (not a login).
        case defaultHandling
        /// Ask the user.
        case ask
        /// Too many refusals: the page shows the server's answer.
        case giveUp
    }

    static func decision(method: String, previousFailureCount: Int) -> Decision {
        guard methods.contains(method) else { return .defaultHandling }
        return previousFailureCount >= maximumAttempts ? .giveUp : .ask
    }

    /// Kept for the session in a normal window; never kept in a private one.
    static func persistence(isPrivate: Bool) -> URLCredential.Persistence {
        isPrivate ? .none : .forSession
    }

    static func title(for request: HTTPAuthenticationRequest) -> String {
        "Log in to \(request.host)"
    }

    static func message(for request: HTTPAuthenticationRequest) -> String {
        var lines: [String] = []
        if let realm = request.realm, !realm.isEmpty {
            lines.append("The site says: “\(realm)”")
        }
        if request.previousFailureCount > 0 {
            lines.append("The name or password was not accepted.")
        }
        if !request.isSecure {
            lines.append("This connection isn't private: the password will be sent unencrypted.")
        }
        return lines.joined(separator: "\n\n")
    }
}
