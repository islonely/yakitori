import XCTest
@testable import WritingTrackerCore

final class ChartDataTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var calendar: CalendarContext!
    private let now = TestSupport.date("2026-09-08T21:00:00-04:00")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        calendar = TestSupport.calendar("America/New_York")
    }

    override func tearDown() {
        database = nil
        calendar = nil
        super.tearDown()
    }

    private func service(now: Date? = nil) -> StatisticsService {
        StatisticsService(database: database, dateProvider: MutableDateProvider(now ?? self.now), calendarContext: calendar)
    }

    private func addSession(
        day: String,
        startHour: Int,
        minutes: Double,
        words: Int,
        type: SessionType = .drafting,
        projectID: String? = nil,
        documentID: String? = nil
    ) throws -> Session {
        let start = TestSupport.date("\(day)T\(String(format: "%02d", startHour)):00:00-04:00")
        let end = start.addingTimeInterval(minutes * 60)
        let session = Session(
            projectID: projectID,
            documentID: documentID,
            startedAt: start,
            endedAt: end,
            activeSeconds: minutes * 60,
            focusSeconds: minutes * 60,
            endingWordCount: words,
            netWordChange: words,
            sessionType: type,
            activeRanges: [TimeRange(start: start, end: end)],
            focusRanges: [TimeRange(start: start, end: end)]
        )
        try SessionRepository(database: database).insert(session)
        return session
    }

    func testMovingAverage() {
        let avg = StatisticsService.movingAverage([10, 20, 30, 40], window: 2)
        XCTAssertNil(avg[0])
        XCTAssertEqual(avg[1]!, 15, accuracy: 0.001)
        XCTAssertEqual(avg[2]!, 25, accuracy: 0.001)
        XCTAssertEqual(avg[3]!, 35, accuracy: 0.001)
    }

    func testTypingPaceCountsOnlyCharacterGrowth() throws {
        // Character samples: 100 -> 130 (+30), 130 -> 120 (deletion, ignored),
        // 120 -> 120 (no change, ignored), 120 -> 150 (+30). Total 60 chars.
        let document = Document(displayName: "Draft.docx")
        try DocumentRepository(database: database).insert(document)
        let start = TestSupport.date("2026-09-08T09:00:00-04:00")
        let session = Session(
            documentID: document.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            activeSeconds: 60,
            activeRanges: [TimeRange(start: start, end: start.addingTimeInterval(60))]
        )
        try SessionRepository(database: database).insert(session)
        let snapshots = [100, 130, 120, 120, 150]
        for (index, count) in snapshots.enumerated() {
            try WordCountSnapshotRepository(database: database).insert(
                WordCountSnapshot(
                    timestamp: start.addingTimeInterval(Double(index) * 10),
                    documentID: document.id,
                    wordCount: 0,
                    characterCount: count,
                    source: "word"
                )
            )
        }
        // 60 characters / 5 = 12 words over 1 minute -> 12 wpm.
        let pace = service().typingPace(for: session)
        XCTAssertEqual(pace ?? 0, 12, accuracy: 0.001)
    }

    func testHourWeekdayMatrixPlacesActivity() throws {
        try addSession(day: "2026-09-07", startHour: 9, minutes: 60, words: 600) // Monday
        try TestSupport.buildAggregates(database, calendar: calendar)
        let cells = service().hourWeekdayMatrix(from: TestSupport.date("2026-09-01T00:00:00-04:00"), to: TestSupport.date("2026-09-15T00:00:00-04:00"))
        let monday9 = cells.first { $0.weekday == 2 && $0.hour == 9 }
        XCTAssertEqual(monday9?.words, 600)
        XCTAssertEqual(monday9?.activeSeconds ?? 0, 3600, accuracy: 1)
    }

    func testSessionTypeBreakdownGroupsByDayAndType() throws {
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 300, type: .drafting)
        try addSession(day: "2026-09-08", startHour: 14, minutes: 30, words: 100, type: .editing)
        let points = service().sessionTypeBreakdown(from: TestSupport.date("2026-09-08T00:00:00-04:00"), to: TestSupport.date("2026-09-09T00:00:00-04:00"))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first { $0.type == .drafting }?.words, 300)
        XCTAssertEqual(points.first { $0.type == .editing }?.words, 100)
    }

    func testAddedRemovedSeriesFromManualEntries() throws {
        let statistics = service()
        let service = SessionService(database: database, statistics: statistics)
        try service.addManualSession(projectID: nil, date: TestSupport.date("2026-09-08T09:00:00-04:00"), words: 500, activeSeconds: 600)
        let points = statistics.addedRemovedSeries(from: TestSupport.date("2026-09-08T00:00:00-04:00"), to: TestSupport.date("2026-09-09T00:00:00-04:00"))
        XCTAssertEqual(points.first?.added, 500)
        XCTAssertEqual(points.first?.removed, 0)
    }

    func testStreakHistoryProducesRuns() throws {
        try addSession(day: "2026-09-06", startHour: 9, minutes: 30, words: 500)
        try addSession(day: "2026-09-07", startHour: 9, minutes: 30, words: 500)
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 500)
        try TestSupport.buildAggregates(database, calendar: calendar)
        let runs = service().streakHistory()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.length, 3)
        XCTAssertTrue(runs.first?.isCurrent ?? false)
    }

    func testMonthlyYearMatrix() throws {
        try addSession(day: "2026-08-15", startHour: 9, minutes: 30, words: 400)
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 700)
        try TestSupport.buildAggregates(database, calendar: calendar)
        let cells = service().monthlyYearMatrix()
        XCTAssertEqual(cells.first { $0.year == 2026 && $0.month == 8 }?.words, 400)
        XCTAssertEqual(cells.first { $0.year == 2026 && $0.month == 9 }?.words, 700)
    }

    func testCareerOutputByYearType() throws {
        let project = Project(title: "Novel", type: .novel)
        try ProjectRepository(database: database).insert(project)
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 500, projectID: project.id)
        let points = service().careerOutputByYearType()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.year, "2026")
        XCTAssertEqual(points.first?.type, .novel)
        XCTAssertEqual(points.first?.words, 500)
    }

    func testCumulativeProjectSeries() throws {
        let project = Project(title: "Cumulative", startingWordCount: 1000, currentWordCount: 1000)
        try ProjectRepository(database: database).insert(project)
        try addSession(day: "2026-09-07", startHour: 9, minutes: 30, words: 200, projectID: project.id)
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 150, projectID: project.id)
        let points = service().cumulativeProjectSeries(projectID: project.id)
        XCTAssertGreaterThanOrEqual(points.count, 3)
        XCTAssertEqual(points.first?.words, 1000)
    }

    func testWeekdayMomentum() throws {
        // now is Tuesday 2026-09-08; this week starts Sunday 2026-09-06.
        try addSession(day: "2026-09-06", startHour: 9, minutes: 30, words: 100)
        try addSession(day: "2026-09-08", startHour: 9, minutes: 30, words: 250)
        try TestSupport.buildAggregates(database, calendar: calendar)
        let points = service().weekdayMomentum(reference: now)
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points[0].thisWeek, 100) // Sunday
        XCTAssertEqual(points[2].thisWeek, 250) // Tuesday
    }
}
