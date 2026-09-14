import XCTest
@testable import WritingTrackerCore

/// Performance coverage for the always-on and compute-heavy paths. These use
/// XCTest `measure` (no pass/fail thresholds) so regressions show up in the
/// reported averages.
final class PerformanceTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var calendar: CalendarContext!
    private var projectIDs: [String] = []
    private let now = TestSupport.date("2026-09-30T21:00:00-04:00")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        calendar = TestSupport.calendar("America/New_York")
        try seed()
    }

    override func tearDown() {
        database = nil
        calendar = nil
        projectIDs = []
        super.tearDown()
    }

    private func seed(sessionCount: Int = 1_200) throws {
        let projectRepo = ProjectRepository(database: database)
        for index in 0..<3 {
            let project = Project(title: "Project \(index)")
            try projectRepo.insert(project)
            projectIDs.append(project.id)
        }
        let repo = SessionRepository(database: database)
        let base = TestSupport.date("2025-01-01T09:00:00-05:00")
        try database.transaction {
            for index in 0..<sessionCount {
                let start = calendar.addingDays(index % 500, to: base)
                let duration = Double(15 + (index % 90)) * 60
                let words = (index % 7 == 0) ? -(index % 200) : (index % 700)
                let session = Session(
                    projectID: projectIDs[index % projectIDs.count],
                    startedAt: start,
                    endedAt: start.addingTimeInterval(duration),
                    activeSeconds: duration,
                    focusSeconds: duration,
                    endingWordCount: words,
                    netWordChange: words,
                    sessionType: SessionType.allCases[index % SessionType.allCases.count],
                    activeRanges: [TimeRange(start: start, end: start.addingTimeInterval(duration))],
                    focusRanges: []
                )
                try repo.insert(session)
            }
        }
        try TestSupport.buildAggregates(database, calendar: calendar)
    }

    private func makeStatistics() -> StatisticsService {
        StatisticsService(database: database, dateProvider: MutableDateProvider(now), calendarContext: calendar)
    }

    func testAggregateRebuildPerformance() throws {
        let builder = DailyAggregateBuilder(calendar: calendar)
        let sessions = try SessionRepository(database: database).all()
        measure {
            _ = builder.aggregates(for: sessions)
        }
    }

    func testLifetimeAndStreakStatisticsPerformance() {
        let statistics = makeStatistics()
        measure {
            _ = statistics.lifetimeStatistics()
            _ = statistics.streakStatistics()
        }
    }

    func testAnalyticsCalculationsPerformance() {
        let statistics = makeStatistics()
        let analytics = AnalyticsService(database: database, statistics: statistics, dateProvider: MutableDateProvider(now))
        let range = DateInterval(start: TestSupport.date("2025-01-01T00:00:00-05:00"), end: now)
        measure {
            _ = analytics.sessionDurationDistribution()
            _ = analytics.dailyOutputDistribution(range: range)
            _ = analytics.productivityBySessionLength()
            _ = analytics.writingCadence()
            _ = analytics.productivityByWorkType()
            _ = analytics.cumulativeLifetimeOutput()
            _ = analytics.outputVariability(window: 7, range: range)
        }
    }

    func testGoalPerformanceCalculationPerformance() throws {
        let goalRepo = GoalRepository(database: database)
        try goalRepo.insert(Goal(period: .daily, metric: .words, target: 400, startDate: TestSupport.date("2025-01-01T00:00:00-05:00")))
        let analytics = AnalyticsService(database: database, statistics: makeStatistics(), dateProvider: MutableDateProvider(now))
        measure {
            _ = analytics.goalPerformance(period: .daily)
        }
    }

    func testStatisticsMathPerformance() {
        let values = (0..<20_000).map { Double($0 % 1_000) }
        measure {
            _ = StatisticsMath.summary(values)
        }
    }

    func testSessionStateMachineThroughputPerformance() {
        measure {
            let machine = SessionStateMachine(policy: SessionPolicy(mode: .manual, inactivityTimeout: 300, endOnAppUnfocus: false))
            _ = machine.handle(.startManually(at: self.now, type: .drafting))
            for index in 0..<2_000 {
                _ = machine.handle(.activity(at: self.now.addingTimeInterval(Double(index))))
            }
            _ = machine.handle(.stopManually(at: self.now.addingTimeInterval(2_001)))
        }
    }

    func testSessionPersistenceThroughputPerformance() {
        let repo = SessionRepository(database: database)
        measure {
            try? self.database.transaction {
                for index in 0..<200 {
                    let session = Session(
                        startedAt: self.now,
                        endedAt: self.now.addingTimeInterval(60),
                        activeSeconds: 60,
                        netWordChange: index
                    )
                    try repo.insert(session)
                }
            }
        }
    }
}
