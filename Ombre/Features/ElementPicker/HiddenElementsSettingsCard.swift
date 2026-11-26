import SwiftUI

/// Settings › Spaces: the elements hidden on each site of a space, each to
/// show again, a site's all at once, or every site's.
struct HiddenElementsSettingsCard: View {
    let container: TabContainer
    @ObservedObject private var store = HiddenElementsStore.shared
    @State private var isConfirmingShowAll = false

    private var sites: [(site: String, elements: [HiddenElement])] {
        store.elements(in: container.id)
            .map { (site: $0.key, elements: $0.value) }
            .sorted { $0.site < $1.site }
    }

    var body: some View {
        SettingsCard(
            header: String(localized: "Hidden Elements"),
            description: String(
                // swiftlint:disable:next line_length
                localized: "Elements hidden with Hide or Capture an Element (⇧⌘H) in \(container.name). They stay hidden on their site from its next load."
            )
        ) {
            let sites = sites
            if sites.isEmpty {
                Text("No element is hidden in this space.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Spacer()
                    Button("Show All…") { isConfirmingShowAll = true }
                }
                ForEach(Array(sites.enumerated()), id: \.element.site) { index, entry in
                    if index > 0 { Divider() }
                    siteSection(entry.site, elements: entry.elements)
                }
            }
        }
        .confirmationDialog(
            "Show all hidden elements in \(container.name)?",
            isPresented: $isConfirmingShowAll
        ) {
            Button("Show All") {
                for entry in sites {
                    store.showAll(onSite: entry.site, in: container.id)
                }
                HiddenElementRuleLists.shared.update(container.id)
            }
        } message: {
            Text("They show again from the next load of their page.")
        }
    }

    private func siteSection(_ site: String, elements: [HiddenElement]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(site).font(.headline)
                Spacer()
                Button("Show All on This Site") {
                    ElementPicker.show(nil, onSite: site, in: container.id)
                }
                .controlSize(.small)
            }
            ForEach(elements) { element in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(element.label)
                        Text(element.selector)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button {
                        ElementPicker.show(element.selector, onSite: site, in: container.id)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Show it again")
                    .accessibilityLabel(String(localized: "Show it again"))
                }
            }
        }
    }
}
