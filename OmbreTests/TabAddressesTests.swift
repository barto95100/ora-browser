import AppKit
import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// "Copy Address" in a tab's context menu: one address per line, in the
    /// sidebar's order.
    @MainActor
    struct TabAddressCopy {
        @Test func oneAddressPerLineInTheGivenOrder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let first = window.addUnloadedTab("/first", order: 1, in: space)
                let second = window.addUnloadedTab("/second?query=1#part", order: 0, in: space)
                #expect(TabAddresses.text(for: [first]) == first.url.absoluteString)
                #expect(TabAddresses.text(for: [second, first])
                    == "\(second.url.absoluteString)\n\(first.url.absoluteString)")
                #expect(TabAddresses.text(for: []).isEmpty)
            }
        }
    }
}
