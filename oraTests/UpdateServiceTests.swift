import Foundation
@testable import Ora
import Testing

struct UpdateServiceTests {
    private let feed = "https://example.com/appcast.xml"
    private let key = "dGVzdC1wdWJsaWMta2V5"

    @Test func missingInfoDictionaryMeansNoUpdates() {
        #expect(!UpdateService.updatesConfigured(in: nil))
        #expect(!UpdateService.updatesConfigured(in: [:]))
    }

    @Test func missingFeedMeansNoUpdates() {
        #expect(!UpdateService.updatesConfigured(in: ["SUPublicEDKey": key]))
    }

    @Test func emptyFeedMeansNoUpdates() {
        #expect(!UpdateService.updatesConfigured(in: ["SUFeedURL": "", "SUPublicEDKey": key]))
        #expect(!UpdateService.updatesConfigured(in: ["SUFeedURL": "  ", "SUPublicEDKey": key]))
    }

    @Test func feedWithoutKeyMeansNoUpdates() {
        #expect(!UpdateService.updatesConfigured(in: ["SUFeedURL": feed]))
        #expect(!UpdateService.updatesConfigured(in: ["SUFeedURL": feed, "SUPublicEDKey": ""]))
    }

    @Test func nonStringValuesMeanNoUpdates() {
        #expect(!UpdateService.updatesConfigured(in: ["SUFeedURL": 1, "SUPublicEDKey": key]))
    }

    @Test func feedAndKeyMeanUpdatesAvailable() {
        #expect(UpdateService.updatesConfigured(in: ["SUFeedURL": feed, "SUPublicEDKey": key]))
    }
}
