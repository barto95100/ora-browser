import Foundation
import os
import SwiftData

private let logger = Logger(category: "SwiftData")

extension ModelContext {
    /// Saves the context and logs a failure instead of swallowing it.
    ///
    /// The caller's behavior doesn't change: a failure is still ignored, it is
    /// just no longer silent. `reason` is a static string so that no page
    /// address or other personal data can end up in it.
    @discardableResult
    func saveOrLog(_ reason: StaticString) -> Bool {
        SaveOrLog.perform(reason) { try save() }
    }
}

/// The logging part of `saveOrLog`, separated so a failure can be tested
/// without having to make SwiftData fail.
enum SaveOrLog {
    @discardableResult
    static func perform(_ reason: StaticString, _ save: () throws -> Void) -> Bool {
        do {
            try save()
            return true
        } catch {
            let nsError = error as NSError
            // The description may hold model values (URLs, titles): private.
            logger.error(
                """
                Save failed (\(reason.description, privacy: .public)): \
                \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \
                \(String(describing: error), privacy: .private)
                """
            )
            return false
        }
    }
}
