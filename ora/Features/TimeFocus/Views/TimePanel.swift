import AppKit
import SwiftUI

/// Browsing time, over the page like the history: a day by hour or a week
/// by day, for this space or all, with the sites that took it.
struct TimePanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.theme) private var theme
    @Environment(\.window) private var window
    @ObservedObject private var store = BrowsingTimeStore.shared
    @ObservedObject private var settings = TimeTrackingSettings.shared

    @State private var period = ReportPeriod.day
    @State private var date = Date()
    @State private var isAllSpaces = true
    @State private var selectedDomain: String?
    @State private var escapeMonitor: Any?

    private var spaceID: UUID? {
        tabManager.activeContainer?.id
    }

    private func report(allSpaces: Bool, domain: String? = nil) -> BrowsingTimeReport {
        _ = store.revision
        return BrowsingTimeReport(
            entries: store.entries(in: period.interval(containing: date)),
            period: period,
            containing: date,
            spaceID: allSpaces ? nil : spaceID,
            domain: domain
        )
    }

    private var isCurrentPeriod: Bool {
        period.interval(containing: date).contains(Date())
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            panel
                .padding(.top, 60)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: watchEscape)
        .onDisappear {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
        }
        .onChange(of: period) { selectedDomain = nil }
    }

    private var panel: some View {
        let shown = report(allSpaces: isAllSpaces, domain: selectedDomain)
        return VStack(alignment: .leading, spacing: 14) {
            toolbar
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard(shown)
                    sitesCard(shown)
                    footnote
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 760, maxHeight: 700)
        .background(theme.launcherMainBackground)
        .background(BlurEffectView(material: .popover, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.foreground.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 40, x: 0, y: 24)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)

            Button { date = period.moving(date, by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help("Previous")
            Text(Self.title(of: period.interval(containing: date), period: period))
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 110)
            Button { date = period.moving(date, by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(isCurrentPeriod)
                .help("Next")
            if !isCurrentPeriod {
                Button("Today") { date = Date() }
                    .buttonStyle(.borderless)
            }
            Spacer()
            Picker("", selection: $isAllSpaces) {
                Text("All Spaces").tag(true)
                Text(tabManager.activeContainer?.name ?? "This Space").tag(false)
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    // MARK: - Summary

    private func summaryCard(_ report: BrowsingTimeReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.compact(report.total))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                if let selectedDomain {
                    Text(selectedDomain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.accent)
                    Button {
                        self.selectedDomain = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .help("All Sites")
                }
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(theme.mutedForeground)
            if !settings.isEnabled {
                Text("Browsing time is off: turn it on in Settings › Time & Focus.")
                    .font(.system(size: 12))
                    .foregroundColor(theme.warning)
            }
            TimeChart(report: report, period: period)
                .frame(height: 190)
                .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    /// "on the web · 4 min in Work".
    private var subtitle: String {
        guard selectedDomain == nil else { return isAllSpaces ? "in all spaces" : "in \(spaceName)" }
        let inSpace = report(allSpaces: false).total
        return isAllSpaces ? "on the web · \(Self.compact(inSpace)) in \(spaceName)" : "on the web in \(spaceName)"
    }

    private var spaceName: String {
        tabManager.activeContainer?.name ?? "this space"
    }

    // MARK: - Sites

    private func sitesCard(_ report: BrowsingTimeReport) -> some View {
        let total = max(report.sites.reduce(0) { $0 + $1.seconds }, 1)
        let longest = report.sites.first?.seconds ?? 1
        return VStack(spacing: 0) {
            HStack {
                Text("SITES")
                Spacer()
                Text("OPENS").frame(width: 60, alignment: .trailing)
                Text("SHARE").frame(width: 56, alignment: .trailing)
                Text("TIME").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(theme.mutedForeground)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if report.sites.isEmpty {
                Text("No browsing time for this period")
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(report.sites) { site in
                siteRow(site, share: site.seconds / total, length: site.seconds / longest)
            }
        }
        .padding(12)
        .background(card)
    }

    private func siteRow(_ site: SiteTime, share: Double, length: Double) -> some View {
        let isSelected = selectedDomain == site.domain
        return Button {
            selectedDomain = isSelected ? nil : site.domain
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    SiteIconView(domain: site.domain)
                    Text(site.domain)
                        .font(.system(size: 13))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)
                    Spacer()
                    Text("\(site.opens)").frame(width: 60, alignment: .trailing)
                    Text("\(Int((share * 100).rounded())) %").frame(width: 56, alignment: .trailing)
                    Text(Self.compact(site.seconds))
                        .foregroundColor(theme.foreground)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(theme.mutedForeground)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.foreground.opacity(0.06))
                        Capsule()
                            .fill(theme.accent.opacity(isSelected ? 1 : 0.7))
                            .frame(width: max(3, geometry.size.width * length))
                    }
                }
                .frame(height: 3)
                .padding(.leading, 28)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? theme.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Browsing Time for \(site.domain)", role: .destructive) {
                if selectedDomain == site.domain { selectedDomain = nil }
                store.delete(domain: site.domain)
            }
        }
    }

    private var footnote: some View {
        Label("Counted on this Mac only", systemImage: "lock")
            .font(.system(size: 11))
            .foregroundColor(theme.mutedForeground)
            .frame(maxWidth: .infinity)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(theme.foreground.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.foreground.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    /// "1h 3min", "7min", "8s".
    static func compact(_ seconds: Double) -> String {
        BrowsingTime.format(seconds).replacingOccurrences(of: " h ", with: "h ")
    }

    /// "Today", "Yesterday", "Monday 26 October", "This Week", "26 Oct – 1 Nov".
    static func title(of interval: DateInterval, period: ReportPeriod, now: Date = Date()) -> String {
        let calendar = Calendar.current
        switch period {
        case .day:
            if calendar.isDateInToday(interval.start) { return "Today" }
            if calendar.isDateInYesterday(interval.start) { return "Yesterday" }
            return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week:
            if interval.contains(now) { return "This Week" }
            let last = interval.end.addingTimeInterval(-1)
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return "\(interval.start.formatted(style)) – \(last.formatted(style))"
        }
    }

    private func watchEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, event.window === (window ?? NSApp.keyWindow) else { return event }
            close()
            return nil
        }
    }

    private func close() {
        appState.showTime = false
    }
}
