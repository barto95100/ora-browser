import Foundation
import os

/// Where the app's identity comes from: the bundle identifier set in
/// project.yml. Logs and internal identifiers derive from it, so changing
/// the identifier there changes them all.
enum AppIdentity {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Ombre"

    /// An identifier of the app's own: `<bundle id>.<name>`.
    static func identifier(_ name: String) -> String {
        "\(bundleIdentifier).\(name)"
    }
}

extension Logger {
    /// A logger of the app, in its subsystem (see `AppIdentity`).
    init(category: String) {
        self.init(subsystem: AppIdentity.bundleIdentifier, category: category)
    }
}
