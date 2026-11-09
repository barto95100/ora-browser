import Foundation
@testable import Ombre
import Testing

/// The French translation ships in the app (the Mac's language picks it).
struct LocalizationTests {
    private func french() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "fr", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func theAppSpeaksFrench() throws {
        let bundle = try french()
        #expect(bundle.localizedString(forKey: "New Tab", value: nil, table: nil) == "Nouvel onglet")
        #expect(bundle
            .localizedString(forKey: "New Private Window", value: nil, table: nil) == "Nouvelle fenêtre privée")
    }

    @Test func aCountAgreesInFrench() throws {
        let format = try french().localizedString(forKey: "%lld blocked on this page", value: nil, table: nil)
        let french = Locale(identifier: "fr_FR")
        #expect(String(format: format, locale: french, 1) == "1 élément bloqué sur cette page")
        #expect(String(format: format, locale: french, 3) == "3 éléments bloqués sur cette page")
    }
}
