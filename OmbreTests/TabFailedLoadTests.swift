import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// A page that cannot load (server down, offline) keeps its address: the
    /// error page offers to retry it, and the tab is saved with it.
    ///
    /// Also checks what the other tests rely on: their pages (see
    /// `TabManagerTestWindow.url`) are refused, not loaded or replaced. A
    /// failure here may mean that port is now in use on this machine, or
    /// blocked by WebKit.
    @MainActor
    struct FailedLoad {
        @Test func refusedLoadKeepsTheTabsAddress() async throws {
            try await TabManagerTestWindow.run { window in
                let url = TabManagerTestWindow.url("refused")
                let tab = try await window.openLoaded("refused")

                // The network error can take several seconds on a busy CI machine.
                await window.waitUntil("load refused", timeout: .seconds(20)) { tab.runtime?.navigationFailure != nil }

                #expect(tab.failedURL == url)
                #expect(tab.url == url)
                #expect(tab.urlString == url.absoluteString)
            }
        }
    }
}
