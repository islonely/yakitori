import XCTest
@testable import WritingTrackerCore

final class StatisticsServiceTests: XCTestCase {
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
        StatisticsService(
            database: database,
            dateProvider: MutableDateProvider(now),
            calendarContext: calendar,
            settings: settings
        )
    }

    @discardableResult
    private func session(
        day: String,
        startHour: Int,
        words: Int,
        activeMinutes: Double,
        projectID: String? = nil,
        type: SessionType = .drafting
    ) throws -> Session {
        let start = TestSupport.date("\(day)T\(String(format: "%02d", startHour)):00:00-04:00")
        let end = start.addingTimeInterval(activeMinutes * 60)
        let session = Session(
            projectID: projectID,
            startedAt: start,
            endedAt: end,
            activeSeconds: activeMinutes * 60,
            focusSeconds: activeMinutes * 60,
            startingWordCount: 0,
            endingWordCount: words,
            netWordChange: words,
            sessionType: type,
            activeRanges: [TimeRange(start: start, end: end)],
            focusRanges: [TimeRange(start: start, end: end)]
        )
        try SessionRepository(database: database).insert(session)
        return session
    }

    func testDailyStatisticsForSingleDay() throws {
        try session(day: "2026-09-08", startHour: 9, words: 600, activeMinutes: 60)
        try session(day: "2026-09-08", startHour: 14, words: 640, activeMinutes: 30)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let stat = service().dailyStatistics(date: now)
        XCTAssertEqual(stat.netWords, 1240)
        XCTAssertEqual(stat.sessionCount, 2)
        XCTAssertEqual(stat.activeSeconds, 5400, accuracy: 0.001)
        XCTAssertTrue(stat.isWritingDay)
        XCTAssertNotNil(stat.wordsPerMinute)
    }

    func testWeeklyStatisticsTotals() throws {
        try session(day: "2026-09-07", startHour: 9, words: 1000, activeMinutes: 60) // Monday
        try session(day: "2026-09-08", startHour: 9, words: 1500, activeMinutes: 90) // Tuesday
        try TestSupport.buildAggregates(database, calendar: calendar)

        // Week of Sep 6 (Sunday) — Sep 12.
        let week = service().weeklyStatistics(startDate: TestSupport.date("2026-09-06T00:00:00-04:00"))
        XCTAssertEqual(week.netWords, 2500)
        XCTAssertEqual(week.sessions, 2)
        XCTAssertEqual(week.writingDays, 2)
        XCTAssertEqual(week.bestDay?.words, 1500)
    }

    func testLifetimeStatistics() throws {
        let projectRepo = ProjectRepository(database: database)
        try projectRepo.insert(TestSupport.makeProject(title: "A", current: 1000))
        var completed = TestSupport.makeProject(title: "B", current: 1000)
        completed.status = .complete
        try projectRepo.insert(completed)

        try session(day: "2026-09-06", startHour: 9, words: 1000, activeMinutes: 60)
        try session(day: "2026-09-07", startHour: 9, words: 2500, activeMinutes: 120)
        try session(day: "2026-09-08", startHour: 9, words: 1200, activeMinutes: 45)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let lifetime = service().lifetimeStatistics()
        XCTAssertEqual(lifetime.lifetimeNetWords, 4700)
        XCTAssertEqual(lifetime.totalSessions, 3)
        XCTAssertEqual(lifetime.writingDays, 3)
        XCTAssertEqual(lifetime.projectCount, 2)
        XCTAssertEqual(lifetime.completedProjects, 1)
        XCTAssertEqual(lifetime.bestDay?.words, 2500)
        XCTAssertEqual(lifetime.bestSessionWords, 2500)
        XCTAssertNotNil(lifetime.mostProductiveMonth)
    }

    func testCurrentAndLongestStreakWithScheduledDayOff() throws {
        var settings = UserSettings.default
        // Schedule: every day except Thursday (weekday 5).
        settings.writingSchedule = (1...7).map { WritingSchedule(weekday: $0, enabled: $0 != 5) }
        settings.streakThresholdKind = .anyWriting

        // Sep 6 (Sun), 7 (Mon), 8 (Tue) = today; Sep 10 (Thu) is a day off.
        try session(day: "2026-09-05", startHour: 9, words: 500, activeMinutes: 30) // Sat
        try session(day: "2026-09-06", startHour: 9, words: 500, activeMinutes: 30) // Sun
        try session(day: "2026-09-07", startHour: 9, words: 500, activeMinutes: 30) // Mon
        try session(day: "2026-09-08", startHour: 9, words: 500, activeMinutes: 30) // Tue
        try TestSupport.buildAggregates(database, calendar: calendar)

        let streaks = service(settings: settings).streakStatistics()
        XCTAssertEqual(streaks.currentStreak, 4)
        XCTAssertEqual(streaks.longestStreak, 4)
    }

    func testStreakThresholdExcludesLowOutputDays() throws {
        var settings = UserSettings.default
        settings.streakThresholdKind = .words500
        try session(day: "2026-09-06", startHour: 9, words: 500, activeMinutes: 30)
        try session(day: "2026-09-07", startHour: 9, words: 200, activeMinutes: 30)
        try session(day: "2026-09-08", startHour: 9, words: 600, activeMinutes: 30)
        try TestSupport.buildAggregates(database, calendar: calendar)

        let streaks = service(settings: settings).streakStatistics()
        XCTAssertEqual(streaks.currentStreak, 1)
        XCTAssertEqual(streaks.longestStreak, 1)
    }

    func testProjectStatisticsAndProjection() throws {
        let project = TestSupport.makeProject(title: "Naphtali", target: 80_000, current: 42_000)
        try ProjectRepository(database: database).insert(project)

        // 7 days of 620 words/day.
        for offset in 0..<7 {
            let day = TestSupport.date("2026-09-02T09:00:00-04:00").addingTimeInterval(Double(offset) * 86_400)
            let dayString = ISO8601DateFormatter.string(from: day, timeZone: TimeZone(identifier: "America/New_York")!, formatOptions: [.withFullDate])
            try session(day: dayString, startHour: 9, words: 620, activeMinutes: 60, projectID: project.id)
        }
        try TestSupport.buildAggregates(database, calendar: calendar)

        let stats = try service().projectStatistics(projectID: project.id)
        XCTAssertEqual(stats.sessionCount, 7)
        XCTAssertEqual(stats.wordsRemaining, 38_000)
        let sevenDay = stats.projections.first { $0.label == "7-day pace" }
        XCTAssertNotNil(sevenDay)
        XCTAssertTrue(sevenDay?.isSufficient ?? false)
        XCTAssertEqual(sevenDay?.wordsPerDay ?? 0, 620, accuracy: 1)
        XCTAssertEqual(sevenDay?.daysRemaining ?? 0, 62)
    }

    func testRebuildAggregatesIsReproducible() throws {
        try session(day: "2026-09-08", startHour: 9, words: 1000, activeMinutes: 60)
        let count = service().rebuildDailyAggregates()
        XCTAssertEqual(count, 1)
        let stat = service().dailyStatistics(date: now)
        XCTAssertEqual(stat.netWords, 1000)
    }
}
