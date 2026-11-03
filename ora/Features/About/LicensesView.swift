import SwiftUI

/// The "Licenses" window (app menu): Ombre's license, where it comes from,
/// and the licenses of the code it includes.
struct LicensesView: View {
    struct Component: Identifiable {
        let name: String
        let license: String
        let url: URL

        var id: String {
            name
        }
    }

    static let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let upstreamURL = URL(string: "https://github.com/the-ora/browser")!

    /// Libraries built into the app (see THIRD_PARTY_NOTICES.md).
    nonisolated static let components: [Component] = [
        Component(
            name: "SafariConverterLib (AdGuard)",
            license: "GPL-3.0",
            url: URL(string: "https://github.com/AdguardTeam/SafariConverterLib")!
        ),
        Component(
            name: "Sparkle",
            license: "MIT and BSD",
            url: URL(string: "https://github.com/sparkle-project/Sparkle")!
        ),
        Component(
            name: "FavIconFinder",
            license: "MIT",
            url: URL(string: "https://github.com/will-lumley/FavIconFinder")!
        ),
        Component(name: "SwiftSoup", license: "MIT", url: URL(string: "https://github.com/scinfu/SwiftSoup")!),
        Component(name: "PunycodeSwift", license: "MIT", url: URL(string: "https://github.com/gumob/PunycodeSwift")!),
        Component(name: "swift-psl", license: "MIT", url: URL(string: "https://github.com/ameshkov/swift-psl")!),
        Component(name: "Public Suffix List data", license: "MPL-2.0", url: URL(string: "https://publicsuffix.org")!),
        Component(
            name: "Swift Argument Parser",
            license: "Apache-2.0",
            url: URL(string: "https://github.com/apple/swift-argument-parser")!
        ),
        Component(
            name: "Inject",
            license: "MIT",
            url: URL(string: "https://github.com/krzysztofzablocki/Inject")!
        ),
        Component(name: "SplitView", license: "MIT", url: URL(string: "https://github.com/stevengharris/SplitView")!)
    ]

    /// The full GPL-3.0 text, bundled with the app.
    private static let licenseText: String = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

    @State private var showsFullLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ombre").font(.title2.weight(.semibold))
                    Text(
                        "Ombre is free software: you can redistribute it and modify it under the terms of the "
                            + "GNU General Public License, version 3."
                    )
                    Link("GNU General Public License v3.0", destination: Self.gplURL)
                    Text("Ombre is derived from Ora Browser (the-ora/browser), licensed under GPL-3.0.")
                        .foregroundStyle(.secondary)
                    Link("github.com/the-ora/browser", destination: Self.upstreamURL)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Third-party components").font(.headline)
                    ForEach(Self.components) { component in
                        HStack {
                            Link(component.name, destination: component.url)
                            Spacer()
                            Text(component.license).foregroundStyle(.secondary)
                        }
                    }
                    Text("Content-blocking filter lists are downloaded from their authors and keep their own licenses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !Self.licenseText.isEmpty {
                    Divider()
                    DisclosureGroup("Full license text", isExpanded: $showsFullLicense) {
                        Text(Self.licenseText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 560)
    }
}
