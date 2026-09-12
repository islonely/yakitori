import XCTest
@testable import WritingTrackerCore

final class SessionRecordingPolicyTests: XCTestCase {
    func testZeroNetWordSessionIsNotRecorded() {
        let session = Session(
            startedAt: Date(),
            endedAt: Date(),
            activeSeconds: 1800,
            focusSeconds: 1800,
            startingWordCount: 1000,
            endingWordCount: 1000,
            netWordChange: 0
        )
        XCTAssertFalse(SessionRecordingPolicy.shouldRecord(session))
    }

    func testPositiveNetWordSessionIsRecorded() {
        let session = Session(
            startedAt: Date(),
            endedAt: Date(),
            activeSeconds: 600,
            focusSeconds: 600,
            startingWordCount: 1000,
            endingWordCount: 1500,
            netWordChange: 500
        )
        XCTAssertTrue(SessionRecordingPolicy.shouldRecord(session))
    }

    func testDeletionOnlySessionIsRecorded() {
        // Removing words is real work and still counts.
        let session = Session(
            startedAt: Date(),
            endedAt: Date(),
            activeSeconds: 600,
            focusSeconds: 600,
            startingWordCount: 1000,
            endingWordCount: 600,
            netWordChange: -400
        )
        XCTAssertTrue(SessionRecordingPolicy.shouldRecord(session))
    }

    func testTimeOnlySessionIsRecordedWhenItHasActivity() {
        let session = Session(startedAt: Date(), endedAt: Date(), activeSeconds: 120, focusSeconds: 120)
        XCTAssertTrue(SessionRecordingPolicy.shouldRecord(session))
    }

    func testEmptyTimeOnlySessionIsNotRecorded() {
        let session = Session(startedAt: Date(), endedAt: Date())
        XCTAssertFalse(SessionRecordingPolicy.shouldRecord(session))
    }

    func testManualSessionWithZeroWordsIsRejected() throws {
        let db = try TestSupport.makeDatabase()
        let statistics = StatisticsService(database: db, dateProvider: MutableDateProvider(), calendarContext: TestSupport.calendar())
        let service = SessionService(database: db, statistics: statistics)
        XCTAssertThrowsError(try service.addManualSession(projectID: nil, date: Date(), words: 0, activeSeconds: 600)) { error in
            XCTAssertEqual(error as? WritingTrackerError, .invalidData(SessionRecordingPolicy.zeroWordRejectionMessage))
        }
        XCTAssertEqual(try SessionRepository(database: db).count(), 0)
    }
}
