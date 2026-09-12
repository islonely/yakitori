import XCTest
@testable import WritingTrackerCore

final class DailyAggregateBuilderTests: XCTestCase {
    func testSessionSpanningMidnightSplitsAcrossDays() {
        let calendar = TestSupport.calendar("America/New_York")
        let start = TestSupport.date("2026-09-08T23:50:00-04:00")
        let end = TestSupport.date("2026-09-09T00:10:00-04:00")
        let session = Session(
            startedAt: start,
            endedAt: end,
            activeSeconds: 1200,
            focusSeconds: 1200,
            activeRanges: [TimeRange(start: start, end: end)],
            focusRanges: [TimeRange(start: start, end: end)]
        )

        let builder = DailyAggregateBuilder(calendar: calendar)
        let aggregates = builder.aggregates(for: [session])
        XCTAssertEqual(aggregates.count, 2)
        XCTAssertEqual(aggregates[0].dayKey, "2026-09-08")
        XCTAssertEqual(aggregates[1].dayKey, "2026-09-09")
        XCTAssertEqual(aggregates[0].activeSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(aggregates[1].activeSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(aggregates[0].sessionCount, 1)
        XCTAssertEqual(aggregates[1].sessionCount, 1)
    }

    func testSessionSpanningSpringForwardDayHasCorrectDuration() {
        // 2026-03-08 02:00–03:00 does not exist in America/New_York.
        let calendar = TestSupport.calendar("America/New_York")
        let start = TestSupport.date("2026-03-08T01:00:00-05:00")
        let end = TestSupport.date("2026-03-08T04:00:00-04:00")
        XCTAssertEqual(end.timeIntervalSince(start), 7200, accuracy: 0.001)

        let session = Session(
            startedAt: start,
            endedAt: end,
            activeSeconds: 7200,
            focusSeconds: 7200,
            activeRanges: [TimeRange(start: start, end: end)],
            focusRanges: [TimeRange(start: start, end: end)]
        )
        let aggregates = DailyAggregateBuilder(calendar: calendar).aggregates(for: [session])
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates[0].dayKey, "2026-03-08")
        XCTAssertEqual(aggregates[0].activeSeconds, 7200, accuracy: 0.001)
    }

    func testSyntheticDistributionForLegacyRowsWithoutRanges() {
        let calendar = TestSupport.calendar("America/New_York")
        let start = TestSupport.date("2026-09-08T22:00:00-04:00")
        let end = TestSupport.date("2026-09-09T02:00:00-04:00")
        // Legacy row: 2 hours of active time over a 4 hour span, no ranges.
        let session = Session(startedAt: start, endedAt: end, activeSeconds: 7200, focusSeconds: 7200)
        let aggregates = DailyAggregateBuilder(calendar: calendar).aggregates(for: [session])
        let total = aggregates.reduce(0.0) { $0 + $1.activeSeconds }
        XCTAssertEqual(total, 7200, accuracy: 1.0)
    }

    func testNetWordsAggregatedWithAddedAndRemovedSeparated() {
        let calendar = TestSupport.calendar("America/New_York")
        let start = TestSupport.date("2026-09-08T10:00:00-04:00")
        let session = Session(
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            activeSeconds: 1800,
            focusSeconds: 1800,
            startingWordCount: 0,
            endingWordCount: -400,
            wordsAdded: 1200,
            wordsRemoved: 1600,
            netWordChange: -400,
            activeRanges: [TimeRange(start: start, end: start.addingTimeInterval(1800))]
        )
        let aggregate = DailyAggregateBuilder(calendar: calendar).aggregates(for: [session]).first
        XCTAssertEqual(aggregate?.wordsAdded, 1200)
        XCTAssertEqual(aggregate?.wordsRemoved, 1600)
        XCTAssertEqual(aggregate?.netWords, -400)
        XCTAssertTrue(aggregate?.isWritingDay ?? false)
    }
}
