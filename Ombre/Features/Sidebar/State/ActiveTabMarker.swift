import Foundation

/// The pill that points to the active tab when its row is scrolled out of
/// the sidebar's tab list: at the top of the list when the row is higher, at
/// its bottom when it is lower; a click scrolls the list to it. Frames are in
/// the list's content coordinates (`coordinateSpace`), which scrolling
/// doesn't change.
enum ActiveTabMarker {
    static let coordinateSpace = "ActiveTabMarker.list"

    enum Edge: Equatable {
        case top
        case bottom
    }

    /// A folder or a group the active tab is in.
    struct Enclosing: Equatable {
        let id: UUID
        /// A closed folder, or a folded group.
        let isFolded: Bool
    }

    /// The rows the pill follows.
    struct Target: Equatable {
        /// The active tab, whose row decides whether the pill shows: a closed
        /// folder or a folded group still shows it.
        let tabID: UUID
        /// Where the pill leads: the tab's row, or that of the outermost
        /// closed folder or folded group it is in (not unfolded).
        let destinationID: UUID
    }

    /// What the list shows: its visible part and its whole height.
    struct Viewport: Equatable {
        let visible: CGRect
        let contentHeight: CGFloat
    }

    /// The rows to follow for the active tab; none for a favorite, always in
    /// view above the list. `enclosing`: its folders, then its group, the
    /// innermost first.
    static func target(tabID: UUID, isFavorite: Bool, enclosing: [Enclosing]) -> Target? {
        guard !isFavorite else { return nil }
        let destination = enclosing.last { $0.isFolded }?.id ?? tabID
        return Target(tabID: tabID, destinationID: destination)
    }

    /// The edge where the pill shows, nil while at least half the row is in
    /// view.
    static func edge(of row: CGRect, in visible: CGRect) -> Edge? {
        guard visible.height > 0 else { return nil }
        if row.midY < visible.minY { return .top }
        if row.midY > visible.maxY { return .bottom }
        return nil
    }

    /// The scroll offset that puts `row` in the middle of the list, as far
    /// as the list can go.
    static func offset(centering row: CGRect, in viewport: Viewport) -> CGFloat {
        let height = viewport.visible.height
        let farthest = max(0, viewport.contentHeight - height)
        return min(max(row.midY - height / 2, 0), farthest)
    }

    /// What VoiceOver says of the pill.
    static func accessibilityLabel(_ edge: Edge) -> String {
        switch edge {
        case .top: String(localized: "Go to Active Tab, Above")
        case .bottom: String(localized: "Go to Active Tab, Below")
        }
    }
}

/// One list's pill: the rows' frames and the viewport come in as they change,
/// and `edge` (what the pill shows) changes only when the answer does.
@MainActor
@Observable
final class ActiveTabMarkerState {
    private(set) var edge: ActiveTabMarker.Edge?

    @ObservationIgnored var target: ActiveTabMarker.Target? {
        didSet { if target != oldValue { update() } }
    }

    @ObservationIgnored var viewport: ActiveTabMarker.Viewport? {
        didSet { if viewport != oldValue { update() } }
    }

    /// A row's frame, with the view that reported it: the same tab can have
    /// two rows a moment (a folder opening), the one leaving must not erase
    /// the other's.
    @ObservationIgnored private var frames: [UUID: (frame: CGRect, reporter: UUID)] = [:]

    func report(_ frame: CGRect, for id: UUID, by reporter: UUID) {
        frames[id] = (frame, reporter)
        update()
    }

    func remove(_ id: UUID, by reporter: UUID) {
        guard frames[id]?.reporter == reporter else { return }
        frames[id] = nil
        update()
    }

    /// Where to scroll to bring the pill's destination to the middle.
    var destinationOffset: CGFloat? {
        guard let target, let viewport,
              let row = frames[target.destinationID]?.frame ?? frames[target.tabID]?.frame
        else { return nil }
        return ActiveTabMarker.offset(centering: row, in: viewport)
    }

    private func update() {
        var newEdge: ActiveTabMarker.Edge?
        if let target, let viewport, let row = frames[target.tabID]?.frame {
            newEdge = ActiveTabMarker.edge(of: row, in: viewport.visible)
        }
        if newEdge != edge { edge = newEdge }
    }
}
