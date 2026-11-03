import SwiftUI

/// The sites of a space blocked during focus: added by hand or from the
/// sites the user spends time on.
struct FocusBlockedSitesView: View {
    let spaceID: UUID
    /// Sites with the most time lately, offered to block.
    var suggestions: [String] = []
    @ObservedObject private var settings = FocusSettings.shared
    @Environment(\.theme) private var theme
    @State private var input = ""
    @State private var isInvalid = false

    private var blocked: [String] {
        settings.blockedSites(in: spaceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("Add a site, like youtube.com", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: input) { isInvalid = false }
                Button("Add", action: add)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isInvalid {
                Text("Not a site address.")
                    .font(.system(size: 11))
                    .foregroundColor(theme.destructive)
            }
            if blocked.isEmpty {
                Text("Nothing is blocked during focus in this space yet.")
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedForeground)
            } else {
                chips(blocked, isBlocked: true)
            }
            let offered = suggestions.filter { !blocked.contains($0) }.prefix(6)
            if !offered.isEmpty {
                Text("From your browsing time")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.mutedForeground)
                chips(Array(offered), isBlocked: false)
            }
        }
    }

    private func chips(_ sites: [String], isBlocked: Bool) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(sites, id: \.self) { site in
                Button {
                    if isBlocked {
                        settings.unblock(site, in: spaceID)
                    } else {
                        settings.block(site, in: spaceID)
                    }
                } label: {
                    HStack(spacing: 5) {
                        SiteIconView(domain: site, size: 14)
                        Text(site).font(.system(size: 11))
                        Image(systemName: isBlocked ? "xmark" : "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(theme.mutedForeground)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(isBlocked ? theme.accent.opacity(0.15) : theme.foreground.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help(isBlocked ? "Unblock \(site)" : "Block \(site) during focus")
            }
        }
    }

    private func add() {
        if settings.block(input, in: spaceID) {
            input = ""
        } else {
            isInvalid = true
        }
    }
}

/// Views placed in rows, going to the next row when full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.top + $0.height } ?? 0
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: left, y: bounds.minY + row.top), proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var top: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(top: row.top + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
