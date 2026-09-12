import XCTest
@testable import WritingTrackerCore

final class WordCountSemanticsTests: XCTestCase {
    func testNetChangeAcrossSamples() {
        // 1000 → 1200 → 1150 → 1300
        let net = WordCountSemantics.netChange(across: [1000, 1200, 1150, 1300])
        XCTAssertEqual(net, 300)
        // Must never be reported as "words written".
        let change = WordCountSemantics.change(from: [1000, 1200, 1150, 1300])
        XCTAssertEqual(change.netChange, 300)
        XCTAssertNil(change.wordsAdded)
        XCTAssertNil(change.wordsRemoved)
        XCTAssertEqual(change.changeLabel, "Net manuscript change")
    }

    func testNegativeNetChangeForDeletions() {
        XCTAssertEqual(WordCountSemantics.netChange(from: 50_000, to: 49_600), -400)
    }

    func testPasteIsCountedAsNetChangeNotTypedWords() {
        XCTAssertEqual(WordCountSemantics.netChange(from: 10_000, to: 15_000), 5_000)
    }

    func testUndoRedoDoesNotDoubleCountNet() {
        XCTAssertEqual(WordCountSemantics.netChange(across: [20_000, 20_500, 20_000]), 0)
    }

    func testEstimatedGrossChangeIsExplicitlyEstimated() {
        let gross = WordCountSemantics.estimatedGrossChange(across: [1000, 1200, 1150, 1300])
        XCTAssertEqual(gross?.added, 350)
        XCTAssertEqual(gross?.removed, 50)
    }

    func testMissingCountsProduceNil() {
        XCTAssertNil(WordCountSemantics.netChange(from: nil, to: 100))
        XCTAssertEqual(WordCountSemantics.change(from: []).changeLabel, "Unavailable")
    }
}
