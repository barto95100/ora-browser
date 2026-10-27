@testable import Ora
import Testing

struct SidebarLayoutTests {
    @Test func minimumIsAFixedWidthWhateverTheWindow() {
        let small = SidebarLayout.minimumFraction(forWindowWidth: 1400)
        let large = SidebarLayout.minimumFraction(forWindowWidth: 2800)

        // Floating-point: compare with a tiny tolerance.
        #expect(abs(small * 1400 - SidebarLayout.minimumWidth) < 0.001)
        #expect(abs(large * 2800 - SidebarLayout.minimumWidth) < 0.001)
    }

    @Test func minimumNeverExceedsTheMaximum() {
        #expect(SidebarLayout.minimumFraction(forWindowWidth: 300) == SidebarLayout.maximumFraction)
        #expect(SidebarLayout.minimumFraction(forWindowWidth: 0) == SidebarLayout.maximumFraction)
    }
}
