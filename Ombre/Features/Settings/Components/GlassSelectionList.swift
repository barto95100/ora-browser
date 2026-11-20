import SwiftUI

/// A list to pick one item from, in a glass panel (macOS 26): the selected
/// row is a pill tinted with the accent color, not a filled bar. The arrow
/// keys move the selection, like a list's.
@available(macOS 26, *)
struct GlassSelectionList<ID: Hashable, Row: View>: View {
    let ids: [ID]
    @Binding var selection: ID?
    @ViewBuilder let row: (ID) -> Row

    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(ids, id: \.self) { id in
                    rowButton(id)
                }
            }
            .padding(8)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
    }

    private func rowButton(_ id: ID) -> some View {
        let isSelected = selection == id
        return Button {
            selection = id
            isFocused = true
        } label: {
            SelectionPillRow(isSelected: isSelected, tint: theme.accent) {
                row(id)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard let next = GlassSelection.next(after: selection, in: ids, by: step) else { return .ignored }
        selection = next
        return .handled
    }
}

/// The selection the arrow keys lead to.
enum GlassSelection {
    /// `step` rows from `current` (the first row if none), kept inside the
    /// list; nil for an empty list.
    static func next<ID: Hashable>(after current: ID?, in ids: [ID], by step: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids[0] }
        return ids[min(max(index + step, 0), ids.count - 1)]
    }
}

/// A row of `GlassSelectionList`. Selected, its pill is drawn behind its
/// icon and name, which stay sharp on top: not glass, which the panel's
/// glass would draw over them.
struct SelectionPillRow<Content: View>: View {
    let isSelected: Bool
    let tint: Color
    @ViewBuilder let content: () -> Content

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        content()
            .fontWeight(isSelected ? .semibold : nil)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isSelected { pill }
            }
            .contentShape(Self.shape)
    }

    /// Tinted, lighter at the top, with a light edge: glass-like.
    private var pill: some View {
        Self.shape
            .fill(tint.opacity(0.32))
            .overlay {
                Self.shape.fill(LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))
            }
            .overlay {
                Self.shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), tint.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
    }
}
