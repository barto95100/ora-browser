import Foundation

/// Where each space's tab list was scrolled, in one window: the sidebar draws
/// only the space shown (see `SpacePager`), and a space left came back at
/// the top.
struct SpaceScrollMemory {
    private var offsets: [UUID: CGFloat] = [:]

    /// The list of `spaceID` is scrolled `offset` points down.
    mutating func note(_ offset: CGFloat, for spaceID: UUID) {
        // At the top (or pulled past it): nothing to put back.
        offsets[spaceID] = offset > 0 ? offset : nil
    }

    /// Where to put the list of `spaceID` back, if it was scrolled.
    func offset(for spaceID: UUID) -> CGFloat? {
        offsets[spaceID]
    }
}
