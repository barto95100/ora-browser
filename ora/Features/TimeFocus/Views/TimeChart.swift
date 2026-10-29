import Charts
import SwiftUI

/// The bars of a day (hours) or a week (days); hovering one tells its time
/// and its main sites.
struct TimeChart: View {
    let report: BrowsingTimeReport
    let period: ReportPeriod
    @Environment(\.theme) private var theme
    @State private var hovered: Date?

    private var hoveredBucket: TimeBucket? {
        guard let hovered else { return nil }
        let calendar = Calendar.current
        return report.buckets.first {
            calendar.isDate($0.start, equalTo: hovered, toGranularity: period.bucketComponent)
        }
    }

    var body: some View {
        Chart(report.buckets) { bucket in
            BarMark(
                x: .value("Time", bucket.start, unit: period.bucketComponent),
                y: .value("Minutes", bucket.seconds / 60)
            )
            .foregroundStyle(
                hoveredBucket?.start == bucket.start ? theme.accent : theme.accent.opacity(0.6)
            )
            .cornerRadius(3)
        }
        .chartXSelection(value: $hovered)
        // At least a minute high: a few seconds made every label "0 min".
        .chartYScale(domain: 0 ... max((report.buckets.map(\.seconds).max() ?? 0) / 60 * 1.1, 1))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.foreground.opacity(0.08))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(TimePanel.compact(minutes * 60))
                    }
                }
            }
        }
        .chartXAxis {
            if period == .day {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            } else {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let bucket = hoveredBucket {
                details(of: bucket)
            }
        }
    }

    private func details(of bucket: TimeBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label(of: bucket.start))
                .font(.system(size: 11, weight: .semibold))
            Text(BrowsingTime.format(bucket.seconds))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            ForEach(bucket.sites) { site in
                HStack(spacing: 6) {
                    Text(site.domain).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(BrowsingTime.format(site.seconds)).monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundColor(theme.mutedForeground)
            }
        }
        .padding(10)
        .frame(width: 190, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
    }

    private func label(of start: Date) -> String {
        if period == .day {
            let end = start.addingTimeInterval(3600)
            let from = start.formatted(date: .omitted, time: .shortened)
            return "\(from) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
