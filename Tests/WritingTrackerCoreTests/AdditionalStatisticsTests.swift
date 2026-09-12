import XCTest
@testable import WritingTrackerCore

final class AdditionalStatisticsTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var calendar: CalendarContext!
    private let now = TestSupport.date("2026-09-08T21:00:00-04:00")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        calendar = TestSupport.calendar("America/New_York")
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    private func service(settings: UserSettings = .default) -> StatisticsService {
        StatisticsService(database: database, dateProvider: MutableDateProvider(now), calendarContext: calendar, settings: settings)
    }

    private func insertSession(start: Date, duration: TimeInterval, words: Int) throws {
        let session = Session(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            activeSeconds: duration,
            focusSeconds: duration,
            endingWordCount: words,
            netWordChange: words,
            activeRanges: [TimeRange(start: start, end: start.addingTimeInterval(duration))],
            focusRanges: [TimeRange(start: start, end: start.addingTimeInterval(duration))]
        )
        try SessionRepository(database: database).insert(session)
    }

    func testHourlyStatisticsAttributesWordsAndTime() throws {
        try insertSession(start: TestSupport.date("2026-09-08T09:00:00-04:00"), duration: 3600, words: 600)
        try insertSession(start: TestSupport.date("2026-09-08T14:00:00-04:00"), duration: 1800, words: 300)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let hours = service().hourlyStatistics(for: now)
        XCTAssertEqual(hours[9].netWords, 600)
        XCTAssertEqual(hours[9].activeSeconds, 3600, accuracy: 1)
        XCTAssertEqual(hours[14].netWords, 300)
        XCTAssertEqual(hours[14].activeSeconds, 1800, accuracy: 1)
    }

    func testGoalProgressDaily() throws {
        try insertSession(start: TestSupport.date("2026-09-08T09:00:00-04:00"), duration: 3600, words: 800)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let stats = service()
        try GoalService(database: database, statistics: stats).createGoal(period: .daily, metric: .words, target: 1000)
        let progress = stats.goalProgress()
        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.first?.currentValue, 800)
        XCTAssertEqual(progress.first?.fraction ?? 0, 0.8, accuracy: 0.001)
        XCTAssertFalse(progress.first?.isComplete ?? true)
    }

    func testMonthlyAndYearlyTotals() throws {
        try insertSession(start: TestSupport.date("2026-08-15T09:00:00-04:00"), duration: 3600, words: 500)
        try insertSession(start: TestSupport.date("2026-09-08T09:00:00-04:00"), duration: 3600, words: 700)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let stats = service()
        XCTAssertEqual(stats.monthlyStatistics(containing: now).netWords, 700)
        XCTAssertEqual(stats.yearlyStatistics(year: 2026).netWords, 1200)
    }

    func testEmptyNewUserStatistics() {
        let stats = service()
        XCTAssertEqual(stats.lifetimeStatistics().lifetimeNetWords, 0)
        XCTAssertEqual(stats.streakStatistics().currentStreak, 0)
        XCTAssertEqual(stats.dailyStatistics(date: now).sessionCount, 0)
        XCTAssertTrue(stats.productivityPatterns().byHour.count == 24)
        XCTAssertFalse(stats.productivityPatterns().hasSufficientData)
    }
}
