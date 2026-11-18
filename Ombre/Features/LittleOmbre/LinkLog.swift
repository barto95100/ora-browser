import Foundation
import os.log

/// Links from other apps, in the app's log ("Links", kept in Release for a
/// problem report): when one came, where it went and why. The site only
/// (see `PageLog.site`), never the rest of the address.
enum LinkLog {
    private static let logger = Logger(category: "Links")

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// `seconds` since Ombre launched, as the log says them.
    static func sinceLaunch(_ seconds: TimeInterval) -> String {
        String(format: "%.1f s after launch", seconds)
    }
}
