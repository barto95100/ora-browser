import SwiftUI

/// Shield of the address bar: how many ads and trackers the page was kept
/// from loading; a click shows them and lets the user turn protections off
/// for the site.
struct PrivacyShieldButton: View {
    @ObservedObject var tab: Tab
    let foregroundColor: Color
    @State private var isShowingPanel = false

    var body: some View {
        Button {
            isShowingPanel.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: tab.areProtectionsEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 11, weight: .medium))
                if tab.blockedContentCount > 0 {
                    Text("\(tab.blockedContentCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundColor(foregroundColor.opacity(tab.areProtectionsEnabled ? 1 : 0.6))
            .frame(minWidth: 16, minHeight: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Privacy protections")
        .accessibilityLabel(Text("Privacy protections, \(tab.blockedContentCount) blocked"))
        .popover(isPresented: $isShowingPanel, arrowEdge: .bottom) {
            PrivacyShieldPanel(tab: tab)
        }
    }
}

private struct PrivacyShieldPanel: View {
    @ObservedObject var tab: Tab

    private var topHosts: [(host: String, count: Int)] {
        tab.blockedContent
            .map { (host: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.host < $1.host }
            .prefix(8)
            .map { $0 }
    }

    private var settings: SpacePrivacySettings {
        tab.privacySettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: tab.areProtectionsEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.protectionSite ?? tab.url.absoluteString)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { tab.areProtectionsEnabled },
                set: { tab.setProtections(enabled: $0) }
            )) {
                Text("Protections for this site")
            }
            .toggleStyle(.switch)
            .disabled(tab.protectionSite == nil || !BrowserPrivacyService.hasContentBlocking(settings))

            if !topHosts.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(topHosts, id: \.host) { entry in
                        HStack {
                            Text(entry.host)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 3) {
                statusLine("Ads", isOn: settings.adBlock.enabled)
                statusLine("Trackers", isOn: settings.blockThirdPartyTrackers)
                HStack {
                    Text("Cookies")
                    Spacer()
                    Text(settings.cookiesPolicy.rawValue).foregroundStyle(.secondary)
                }
                Text("Change them in Settings › Spaces.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var summary: String {
        if !BrowserPrivacyService.hasContentBlocking(settings) {
            return "No blocking is set up in this space"
        }
        if !tab.areProtectionsEnabled {
            return "Protections are off for this site"
        }
        let count = tab.blockedContentCount
        return count == 0 ? "Nothing blocked on this page" : "\(count) blocked on this page"
    }

    private func statusLine(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isOn ? "On" : "Off").foregroundStyle(.secondary)
        }
    }
}
