import Foundation
@testable import Ora
import Testing

struct FingerprintingNoiseSeedTests {
    private let space = UUID()
    private let otherSpace = UUID()

    @Test func seedIsStableForTheSameSpaceAndSession() {
        let first = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 42)
        let second = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 42)

        #expect(first == second)
    }

    @Test func spacesDoNotShareNoise() {
        let first = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 42)
        let second = FingerprintingNoiseSeed.seed(spaceID: otherSpace, isPrivate: false, secret: 42)

        #expect(first != second)
    }

    @Test func privateBrowsingDoesNotShareNoiseWithItsSpace() {
        let regular = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 42)
        let privateBrowsing = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: true, secret: 42)

        #expect(regular != privateBrowsing)
    }

    @Test func noiseChangesFromOneSessionToTheNext() {
        let session1 = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 1)
        let session2 = FingerprintingNoiseSeed.seed(spaceID: space, isPrivate: false, secret: 2)

        #expect(session1 != session2)
    }

    @Test func scriptMixesTheSeedWithTheSite() {
        let script = BrowserPrivacyService.fingerprintingProtectionScriptSource(seed: 123_456_789)

        #expect(script.contains("123456789"))
        #expect(script.contains("ancestorOrigins"))
        #expect(script.contains("siteSeed"))
    }
}
