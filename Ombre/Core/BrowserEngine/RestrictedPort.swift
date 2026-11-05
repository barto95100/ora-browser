import Foundation

/// Ports browsers never load web pages from, because other services use them
/// (mail, ssh…): the Fetch standard's "bad ports", which WebKit refuses too.
/// WebKit then shows a blank page without telling the app; Ombre shows an
/// error page instead, like Safari.
enum RestrictedPort {
    static let ports: Set<Int> = [
        0, 1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103,
        104, 109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514,
        515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049,
        3659, 4045, 4190, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080
    ]

    /// WebKit's own code for it (`WebKitErrorCannotUseRestrictedPort`).
    static let errorCode = 103

    static func isRestricted(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "ws", "wss"].contains(scheme),
              let port = url.port
        else { return false }
        return ports.contains(port)
    }

    static func error(for url: URL) -> NSError {
        NSError(domain: "WebKitErrorDomain", code: errorCode, userInfo: [
            NSLocalizedDescriptionKey: "Not allowed to use restricted network port",
            NSURLErrorFailingURLErrorKey: url
        ])
    }
}
