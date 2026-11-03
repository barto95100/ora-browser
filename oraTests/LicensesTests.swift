import Foundation
@testable import Ora
import Testing

@MainActor
struct LicensesTests {
    /// The Swift packages the app is built with (Package.resolved).
    private func resolvedPackageURLs() throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let resolved = root.appending(path: "Ora.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let pins = json?["pins"] as? [[String: Any]] ?? []
        return pins.compactMap { $0["location"] as? String }
    }

    private func normalized(_ location: String) -> String {
        location.lowercased().replacingOccurrences(of: ".git", with: "")
    }

    @Test func everyPackageIsListedInTheLicensesWindow() throws {
        let listed = Set(LicensesView.components.map { normalized($0.url.absoluteString) })
        let packages = try resolvedPackageURLs()
        #expect(!packages.isEmpty)
        for package in packages {
            #expect(listed.contains(normalized(package)), "\(package) is missing from LicensesView.components")
        }
    }

    @Test func theLicenseTextIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "LICENSE", withExtension: nil))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Version 3"))
    }
}
