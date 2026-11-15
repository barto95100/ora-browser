import Foundation
@testable import Ombre
import Testing

/// Each space's list comes back where it was left.
struct SpaceScrollMemoryTests {
    private let work = UUID()
    private let home = UUID()

    @Test func eachSpaceKeepsItsOwnScroll() {
        var memory = SpaceScrollMemory()
        memory.note(320, for: work)
        memory.note(40, for: home)
        #expect(memory.offset(for: work) == 320)
        #expect(memory.offset(for: home) == 40)
        #expect(memory.offset(for: UUID()) == nil)
    }

    /// Back at the top (or pulled past it, a bounce): nothing to restore.
    @Test(arguments: [0, -12] as [CGFloat])
    func atTheTopNothingIsKept(offset: CGFloat) {
        var memory = SpaceScrollMemory()
        memory.note(320, for: work)
        memory.note(offset, for: work)
        #expect(memory.offset(for: work) == nil)
    }
}
