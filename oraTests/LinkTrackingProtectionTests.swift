import Foundation
@testable import Ora
import Testing

struct LinkTrackingProtectionTests {
    @Test func campaignTagsAndClickIDsAreTakenOff() throws {
        let url = try #require(URL(string: "https://example.com/article?id=42&utm_source=news&fbclid=abc&gclid=x"))
        #expect(LinkTrackingProtection.cleaned(url)?.absoluteString == "https://example.com/article?id=42")
    }

    @Test func aURLWithOnlyTrackingLosesItsQuery() throws {
        let url = try #require(URL(string: "https://example.com/?utm_campaign=fall&UTM_MEDIUM=mail"))
        #expect(LinkTrackingProtection.cleaned(url)?.absoluteString == "https://example.com/")
    }

    @Test func aURLWithoutTrackingIsLeftAlone() throws {
        let url = try #require(URL(string: "https://example.com/search?q=utm&page=2"))
        #expect(LinkTrackingProtection.cleaned(url) == nil)
    }

    @Test func theFragmentIsKept() throws {
        let url = try #require(URL(string: "https://example.com/doc?msclkid=1#section"))
        #expect(LinkTrackingProtection.cleaned(url)?.absoluteString == "https://example.com/doc#section")
    }

    @Test func otherSchemesAreLeftAlone() throws {
        let url = try #require(URL(string: "file:///tmp/page.html?utm_source=x"))
        #expect(LinkTrackingProtection.cleaned(url) == nil)
    }
}
