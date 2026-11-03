import Foundation
@testable import Ombre
import Testing

struct AppIdentityTests {
    @Test func identityComesFromTheBundleIdentifier() throws {
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(AppIdentity.bundleIdentifier == bundleID)
        #expect(AppIdentity.identifier("adblock") == "\(bundleID).adblock")
    }
}
