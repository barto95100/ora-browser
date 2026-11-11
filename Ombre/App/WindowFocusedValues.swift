import SwiftUI

/// What the menus need to know about the browser window in front.
extension FocusedValues {
    /// Whether the window in front shows Peek (nil: no browser window in front).
    @Entry var isPeekOpen: Bool?
}
