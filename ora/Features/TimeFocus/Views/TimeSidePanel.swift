import SwiftUI

/// Today's browsing time beside the page, like the tasks: the total, the
/// hours, the main sites; the details open in the large panel (`TimePanel`).
struct TimeSidePanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @ObservedObject private var store = BrowsingTimeStore.shared
    @ObservedObject private var settings = TimeTrackingSettings.shared

    private static let shownSites = 6

    private func report(spaceID: UUID? = nil) -> BrowsingTimeReport {
        _ = store.revision
        let today = Date()
        return BrowsingTimeReport(
            entries: store.entries(in: ReportPeriod.day.interval(containing: today)),
            period: .day,
            containing: today,
            spaceID: spaceID
        )
    }

    var body: some View {
        let report = report()
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(report)
                    TimeChart(report: report, period: .day)
                        .frame(height: 110)
                    sites(report)
                    Button {
                        appState.showTime = true
                    } label: {
                        Label("Show Details", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundColor(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Browsing Time (⌥⌘Y)")
                }
                .padding(14)
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Browsing Time")
                    .font(.system(size: 13, weight: .semibold))
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
            }
            Spacer(minLength: 0)
            Button {
                appState.showTime = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("Show Details (⌥⌘Y)")
            Button {
                appState.showTimeSummary = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .foregroundColor(theme.foreground.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func summary(_ report: BrowsingTimeReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TimePanel.compact(report.total))
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
            if let space = tabManager.activeContainer {
                Text("on the web · \(TimePanel.compact(self.report(spaceID: space.id).total)) in \(space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
            }
            if !settings.isEnabled {
                Text("Browsing time is off: Settings › Time & Focus.")
                    .font(.system(size: 11))
                    .foregroundColor(theme.warning)
            }
        }
    }

    private func sites(_ report: BrowsingTimeReport) -> some View {
        let longest = report.sites.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            if report.sites.isEmpty {
                Text("No browsing time today")
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
            }
            ForEach(report.sites.prefix(Self.shownSites)) { site in
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        SiteIconView(domain: site.domain, size: 16)
                        Text(site.domain)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(TimePanel.compact(site.seconds))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(theme.mutedForeground)
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(theme.accent.opacity(0.7))
                            .frame(width: max(3, geometry.size.width * site.seconds / longest))
                    }
                    .frame(height: 3)
                    .padding(.leading, 24)
                }
            }
            if report.sites.count > Self.shownSites {
                Text("and \(report.sites.count - Self.shownSites) more")
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
            }
        }
    }
}
