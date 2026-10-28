import Foundation

extension Tab {
    /// Leaves its split without moving the other tab, which shows again at its
    /// own place (this tab is moving to another section).
    func leaveSplit() {
        splitRightTabID = nil
        for other in container.tabs where other.splitRightTabID == id {
            other.splitRightTabID = nil
        }
    }
}
