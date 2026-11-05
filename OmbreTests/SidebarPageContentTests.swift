import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// The spaces' pages in the sidebar are made once (`NSPageView`): what they
/// show must not be fixed at that time (INT-06).
@MainActor
struct SidebarPageContentTests {
    private struct Label: View, Equatable {
        let text: String
        var body: some View {
            Text(text)
        }
    }

    /// A page made later shows the content the pager has now, not the one it
    /// had when it was made.
    @Test func pagesMadeLaterShowCurrentContent() {
        let controller = NSPageViewContainerController<String, Label>()
        controller.objectToView = { _ in Label(text: "when made") }
        let view = NSPageView(selection: .constant(0), pageObjects: ["a"], idKeyPath: \.self) { _ in
            Label(text: "now")
        }

        view.refresh(controller)

        #expect(controller.objectToView?("a") == Label(text: "now"))
    }
}
