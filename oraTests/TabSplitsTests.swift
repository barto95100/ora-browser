import Foundation
@testable import Ora
import Testing

struct TabSplitsTests {
    private let ids = (0 ..< 4).map { _ in UUID() }

    @Test func aTabShowingAnotherAtItsRightFormsAPair() {
        let pairs = TabSplits.pairs([
            .init(id: ids[0], rightID: ids[1]),
            .init(id: ids[1], rightID: nil)
        ])
        #expect(pairs == [ids[0]: ids[1]])
    }

    @Test func aPairWhoseRightTabIsGoneIsIgnored() {
        let pairs = TabSplits.pairs([.init(id: ids[0], rightID: ids[3])])
        #expect(pairs.isEmpty)
    }

    @Test func aTabCannotBeSplitWithItself() {
        let pairs = TabSplits.pairs([.init(id: ids[0], rightID: ids[0])])
        #expect(pairs.isEmpty)
    }

    @Test func aTabIsInOnePairAtMost() {
        let pairs = TabSplits.pairs([
            .init(id: ids[0], rightID: ids[1]),
            .init(id: ids[1], rightID: ids[2]),
            .init(id: ids[2], rightID: nil),
            .init(id: ids[3], rightID: ids[1])
        ])
        #expect(pairs == [ids[0]: ids[1]])
    }

    @Test func thePartnerIsFoundFromEitherSide() {
        let pairs = [ids[0]: ids[1]]
        #expect(TabSplits.partner(of: ids[0], in: pairs) == ids[1])
        #expect(TabSplits.partner(of: ids[1], in: pairs) == ids[0])
        #expect(TabSplits.partner(of: ids[2], in: pairs) == nil)
    }

    @Test func bothSidesKeepAUsableWidth() {
        #expect(TabSplits.clampedFraction(0.05) == TabSplits.minimumFraction)
        #expect(TabSplits.clampedFraction(0.97) == 1 - TabSplits.minimumFraction)
        #expect(TabSplits.clampedFraction(0.5) == 0.5)
    }
}
