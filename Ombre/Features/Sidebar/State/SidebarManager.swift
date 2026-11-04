import Combine
import SwiftUI

enum SidebarPosition: String, Hashable {
    /// Where the position is kept (shared by every window).
    static let defaultsKey = "ui.sidebar.position"

    case primary
    case secondary

    /// The side of the split view that holds the sidebar.
    var splitSide: SplitSide {
        self == .primary ? .primary : .secondary
    }
}

/// The sidebar of one browser window. Its position (left or right) is shared
/// by every window; whether it is hidden belongs to each window and is not
/// remembered: every window opens with its sidebar shown.
@MainActor
class SidebarManager: ObservableObject {
    /// Keys of earlier versions, which shared the hidden state between windows
    /// and launches.
    nonisolated static let obsoleteDefaultsKeys = ["ui.sidebar.hidden", "ui.sidebar.visibility"]

    @AppStorage(SidebarPosition.defaultsKey) var sidebarPosition: SidebarPosition = .primary

    @Published var primaryFraction = FractionHolder.usingUserDefaults(0.2, key: "ui.sidebar.fraction.primary")
    @Published var secondaryFraction = FractionHolder.usingUserDefaults(0.2, key: "ui.sidebar.fraction.secondary")
    @Published var hiddenSidebar = SideHolder()

    private var hiddenSidebarObserver: AnyCancellable?

    init() {
        // The views observe this manager: tell them when the split view hides
        // a side (toggle or drag).
        hiddenSidebarObserver = hiddenSidebar.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Removes the keys of earlier versions from the user defaults.
    nonisolated static func removeObsoleteDefaults(_ defaults: UserDefaults = .standard) {
        for key in obsoleteDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    var isSidebarHidden: Bool {
        hiddenSidebar.side != nil
    }

    var currentFraction: FractionHolder {
        sidebarPosition == .primary ? primaryFraction : secondaryFraction
    }

    func toggleSidebar() {
        let targetSide = sidebarPosition.splitSide
        withAnimation(.spring(response: 0.2, dampingFraction: 1.0)) {
            hiddenSidebar.side = (hiddenSidebar.side == targetSide) ? nil : targetSide
        }
    }

    /// Moves the sidebar to the other side, in every window: each window then
    /// follows with `sidebarPositionChanged(from:to:)`.
    func toggleSidebarPosition() {
        sidebarPosition = sidebarPosition == .primary ? .secondary : .primary
    }

    /// Keeps this window's sidebar hidden after it moved to the other side.
    func sidebarPositionChanged(from oldPosition: SidebarPosition, to newPosition: SidebarPosition) {
        hiddenSidebar.side = Self.hiddenSide(hiddenSidebar.side, from: oldPosition, to: newPosition)
    }

    /// The side to hide once the sidebar moved from `oldPosition` to
    /// `newPosition`: a hidden sidebar stays hidden, never the page.
    nonisolated static func hiddenSide(
        _ side: SplitSide?,
        from oldPosition: SidebarPosition,
        to newPosition: SidebarPosition
    ) -> SplitSide? {
        side == oldPosition.splitSide ? newPosition.splitSide : side
    }
}
