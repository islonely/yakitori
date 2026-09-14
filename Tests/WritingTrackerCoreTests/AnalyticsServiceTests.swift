import XCTest
@testable import WritingTrackerCore

final class StatisticsMathTests: XCTestCase {
    func testPercentileLinearInterpolation() {
        let values: [Double] = [10, 20, 30, 40]
        XCTAssertEqual(StatisticsMath.percentile(values, 0.5), 25, accuracy: 0.001)
        XCTAssertEqual(StatisticsMath.percentile(values, 0.25), 17.5, accuracy: 0.001)
        XCTAssertEqual(StatisticsMath.percentile(values, 0), 10, accuracy: 0.001)
        XCTAssertEqual(StatisticsMath.percentile(values, 1), 40, accuracy: 0.001)
    }

    func testMedianHandlesEvenAndOddCounts() {
        XCTAssertEqual(StatisticsMath.median([1, 2, 3]), 2, accuracy: 0.001)
        XCTAssertEqual(StatisticsMath.median([1, 2, 3, 4]), 2.5, accuracy: 0.001)
    }

    func testSampleStandardDeviation() {
        XCTAssertEqual(StatisticsMath.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9]), 2.138, accuracy: 0.01)
        XCTAssertEqual(StatisticsMath.standardDeviation([5]), 0, accuracy: 0.001)
        XCTAssertEqual(StatisticsMath.standardDeviation([]), 0, accuracy: 0.001)
    }

    func testBinCountsIncludeLastEdge() {
        let counts = StatisticsMath.binCounts([0, 5, 9, 10, 15], edges: [0, 10, 20])
        XCTAssertEqual(counts, [3, 2])
    }

    func testEqualWidthEdgesReturnsNilForIdenticalValues() {
        XCTAssertNil(StatisticsMath.equalWidthEdges([42, 42, 42], binCount: 5))
        XCTAssertNotNil(StatisticsMath.equalWidthEdges([0, 10], binCount: 5))
    }
}

final class AnalyticsServiceTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var calendar: CalendarContext!
    private let now = TestSupport.date("2026-09-30T21:00:00-04:00")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        calendar = TestSupport.calendar("America/New_York")
    }

    override func tearDown() {
        database = nil
        calendar = nil
        super.tearDown()
    }

    private func statistics() -> StatisticsService {
        StatisticsService(database: database, dateProvider: MutableDateProvider(now), calendarContext: calendar)
    }

    private func analytics() -> AnalyticsService {
        AnalyticsService(database: database, statistics: statistics(), dateProvider: MutableDateProvider(now))
    }

    private func dayAt(_ offset: Int, hour: Int) -> Date {
        let base = TestSupport.date("2026-09-01T\(String(format: "%02d", hour)):00:00-04:00")
        return calendar.addingDays(offset, to: base)
    }

    @discardableResult
    private func insertSession(
        start: Date,
        durationMinutes: Double,
        activeMinutes: Double? = nil,
        words: Int? = nil,
        added: Int? = nil,
        removed: Int? = nil,
        type: SessionType = .drafting,
        projectID: String? = nil
    ) throws -> Session {
        let end = start.addingTimeInterval(durationMinutes * 60)
        let active = (activeMinutes ?? durationMinutes) * 60
        let session = Session(
            projectID: projectID,
            startedAt: start,
            endedAt: end,
            activeSeconds: active,
            focusSeconds: active,
            endingWordCount: words,
            wordsAdded: added,
            wordsRemoved: removed,
            netWordChange: words,
            sessionType: type,
            activeRanges: active > 0 ? [TimeRange(start: start, end: start.addingTimeInterval(active))] : [],
            focusRanges: []
        )
        try SessionRepository(database: database).insert(session)
        return session
    }

    private func buildAggregates() throws {
        try TestSupport.buildAggregates(database, calendar: calendar)
    }

    // MARK: 1. Session duration

    func testSessionDurationDistribution() throws {
        for minutes in [10.0, 20, 30, 40, 50] {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: minutes, words: 100)
        }
        let distribution = analytics().sessionDurationDistribution()
        XCTAssertEqual(distribution.sessionCount, 5)
        XCTAssertEqual(distribution.summary.median, 30, accuracy: 0.001)
        XCTAssertEqual(distribution.summary.mean, 30, accuracy: 0.001)
        XCTAssertEqual(distribution.summary.minimum, 10, accuracy: 0.001)
        XCTAssertEqual(distribution.summary.maximum, 50, accuracy: 0.001)
        XCTAssertEqual(distribution.bins.map(\.count).reduce(0, +), 5)
    }

    func testSessionDurationExcludesZeroAndInvalidDurations() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 100)
        // Zero duration.
        try SessionRepository(database: database).insert(
            Session(startedAt: dayAt(0, hour: 9), endedAt: dayAt(0, hour: 9), activeSeconds: 0, netWordChange: 50)
        )
        // Negative duration (ended before started) collapses to zero.
        try SessionRepository(database: database).insert(
            Session(startedAt: dayAt(0, hour: 10), endedAt: dayAt(0, hour: 9), activeSeconds: 0, netWordChange: 50)
        )
        let distribution = analytics().sessionDurationDistribution()
        XCTAssertEqual(distribution.sessionCount, 1)
    }

    func testEmptySessionDurationDistribution() {
        let distribution = analytics().sessionDurationDistribution()
        XCTAssertTrue(distribution.isEmpty)
        XCTAssertEqual(distribution.summary.count, 0)
        XCTAssertTrue(distribution.bins.isEmpty)
    }

    // MARK: 2. Daily output distribution

    func testDailyOutputDistributionIncludesNegativeAndZeroDays() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 500)
        try insertSession(start: dayAt(1, hour: 9), durationMinutes: 30, words: -200)
        try insertSession(start: dayAt(2, hour: 9), durationMinutes: 30, words: 0)
        try buildAggregates()
        let distribution = analytics().dailyOutputDistribution(range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(5, hour: 0)))
        XCTAssertEqual(distribution.writingDayCount, 3)
        XCTAssertEqual(distribution.summary.maximum, 500, accuracy: 0.001)
        XCTAssertEqual(distribution.summary.minimum, -200, accuracy: 0.001)
        XCTAssertEqual(distribution.bins.map(\.count).reduce(0, +), 3)
    }

    func testDailyOutputDistributionGrossUsesAddedAndRemoved() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: -100, added: 400, removed: 500)
        try buildAggregates()
        let gross = analytics().dailyOutputDistribution(range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(2, hour: 0)), metric: .grossWorked)
        XCTAssertEqual(gross.summary.maximum, 900, accuracy: 0.001)
        XCTAssertTrue(gross.metric.isEstimated)
    }

    func testDailyOutputDistributionEmptyRange() {
        let distribution = analytics().dailyOutputDistribution(range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(2, hour: 0)))
        XCTAssertTrue(distribution.isEmpty)
    }

    // MARK: 3. Productivity by session length

    func testProductivityBySessionLengthUsesMedianAndBins() throws {
        // Three 45-minute sessions at 120 words/hour.
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 45, activeMinutes: 45, words: 90)
        }
        let result = analytics().productivityBySessionLength()
        let bin = result.bins.first { $0.label == "30-60 min" }
        XCTAssertNotNil(bin)
        XCTAssertTrue(bin?.isSufficient ?? false)
        XCTAssertEqual(bin?.medianWordsPerHour ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(bin?.sampleCount, 3)
    }

    func testProductivityBySessionLengthResistsOutliers() throws {
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 45, words: 90)
        }
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 45, words: 9000)
        let result = analytics().productivityBySessionLength()
        let bin = result.bins.first { $0.label == "30-60 min" }
        XCTAssertEqual(bin?.medianWordsPerHour ?? 0, 120, accuracy: 0.001)
    }

    func testProductivityBySessionLengthMarksInsufficientBins() throws {
        for _ in 0..<2 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 45, words: 90)
        }
        let result = analytics().productivityBySessionLength()
        let bin = result.bins.first { $0.label == "30-60 min" }
        XCTAssertFalse(bin?.isSufficient ?? true)
        XCTAssertFalse(result.hasSufficientBins)
    }

    func testProductivityBySessionLengthIgnoresZeroActiveTime() throws {
        for _ in 0..<4 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 45, activeMinutes: 0, words: 90)
        }
        let result = analytics().productivityBySessionLength()
        XCTAssertFalse(result.hasSufficientBins)
    }

    // MARK: 4. Goal performance

    func testGoalPerformanceMetMissedAndIncompletePeriods() throws {
        let goalRepo = GoalRepository(database: database)
        try goalRepo.insert(
            Goal(period: .daily, metric: .words, target: 100, startDate: dayAt(0, hour: 0))
        )
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 150) // met
        try insertSession(start: dayAt(1, hour: 9), durationMinutes: 30, words: 50)  // missed
        try buildAggregates()

        let history = analytics().goalPerformance(period: .daily)
        // now is Sep 30; goal started Sep 1, so many completed days exist. The two
        // days with data should be reflected in the results.
        XCTAssertFalse(history.isEmpty)
        XCTAssertGreaterThanOrEqual(history.met, 1)
        let met = history.results.first { $0.actual == 150 }
        XCTAssertEqual(met?.attainment ?? 0, 150, accuracy: 0.001)
        let missed = history.results.first { $0.actual == 50 }
        XCTAssertLessThan(missed?.attainment ?? 100, 100)
    }

    func testGoalPerformanceSeparatesPeriods() throws {
        let goalRepo = GoalRepository(database: database)
        try goalRepo.insert(Goal(period: .daily, metric: .words, target: 100, startDate: dayAt(0, hour: 0)))
        try goalRepo.insert(Goal(period: .weekly, metric: .words, target: 500, startDate: dayAt(0, hour: 0)))
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 150)
        try buildAggregates()

        let service = analytics()
        let daily = service.goalPerformance(period: .daily)
        let weekly = service.goalPerformance(period: .weekly)
        XCTAssertEqual(daily.period, .daily)
        XCTAssertEqual(weekly.period, .weekly)
        XCTAssertNotEqual(daily.results.count, 0)
        XCTAssertNotEqual(weekly.results.count, 0)
    }

    func testGoalPerformanceZeroTargetDoesNotDivideByZero() throws {
        let goalRepo = GoalRepository(database: database)
        try goalRepo.insert(Goal(period: .daily, metric: .words, target: 0, startDate: dayAt(0, hour: 0)))
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 100)
        try buildAggregates()
        let history = analytics().goalPerformance(period: .daily)
        XCTAssertFalse(history.results.isEmpty)
        XCTAssertEqual(history.results.first?.attainment ?? -1, 0, accuracy: 0.001)
    }

    func testGoalPerformanceEmptyWithoutGoals() {
        XCTAssertTrue(analytics().goalPerformance(period: .daily).isEmpty)
    }

    // MARK: 5. Project velocity

    func testProjectVelocityFiltersByProjectAndComputesRolling() throws {
        let projectRepo = ProjectRepository(database: database)
        let project = Project(title: "Velocity")
        let other = Project(title: "Other")
        try projectRepo.insert(project)
        try projectRepo.insert(other)
        // Seven consecutive days of 100 words for the project, plus unrelated activity.
        for offset in 0..<7 {
            try insertSession(start: dayAt(offset, hour: 9), durationMinutes: 30, words: 100, projectID: project.id)
        }
        try insertSession(start: dayAt(3, hour: 9), durationMinutes: 30, words: 9999, projectID: other.id)

        let velocity = analytics().projectVelocity(projectID: project.id, granularity: .daily)
        XCTAssertTrue(velocity.hasSufficientData)
        XCTAssertTrue(velocity.hasRollingSeries)
        // The other project's outlier must not appear in this project's totals.
        XCTAssertFalse(velocity.points.contains { $0.words == 9999 })
        let last = velocity.points.last
        XCTAssertEqual(last?.rollingAverage ?? 0, 100, accuracy: 0.001)
    }

    func testProjectVelocitySparseDataHasNoRollingSeries() throws {
        let project = Project(title: "Sparse")
        try ProjectRepository(database: database).insert(project)
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 100, projectID: project.id)
        let velocity = analytics().projectVelocity(projectID: project.id, granularity: .daily)
        XCTAssertFalse(velocity.hasSufficientData)
        XCTAssertFalse(velocity.hasRollingSeries)
    }

    // MARK: 6. Writing cadence

    func testWritingCadenceExcludesFirstSessionAndMeasuresGaps() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, words: 100)
        try insertSession(start: dayAt(0, hour: 11), durationMinutes: 60, words: 100) // 1h gap
        try insertSession(start: dayAt(1, hour: 9), durationMinutes: 60, words: 100)  // 22h gap
        let cadence = analytics().writingCadence()
        XCTAssertEqual(cadence.gapCount, 2)
        XCTAssertEqual(cadence.summary.minimum, 60, accuracy: 1)
    }

    func testWritingCadenceHandlesCrossMidnight() throws {
        try insertSession(start: dayAt(0, hour: 23), durationMinutes: 120, words: 100) // 23:00 -> 01:00
        try insertSession(start: dayAt(1, hour: 2), durationMinutes: 30, words: 50)
        let cadence = analytics().writingCadence()
        XCTAssertEqual(cadence.gapCount, 1)
        XCTAssertEqual(cadence.summary.median, 60, accuracy: 1)
    }

    func testWritingCadenceIgnoresOverlaps() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 120, words: 100)
        try insertSession(start: dayAt(0, hour: 10), durationMinutes: 30, words: 100) // overlaps previous
        let cadence = analytics().writingCadence()
        XCTAssertEqual(cadence.gapCount, 0)
        XCTAssertTrue(cadence.isEmpty)
    }

    // MARK: 7. Project effort by phase

    func testEffortByPhaseNormalizesActiveTime() throws {
        let project = Project(title: "Phases")
        try ProjectRepository(database: database).insert(project)
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, activeMinutes: 60, words: 100, type: .drafting, projectID: project.id)
        try insertSession(start: dayAt(1, hour: 9), durationMinutes: 40, activeMinutes: 40, words: 10, type: .editing, projectID: project.id)
        let efforts = analytics().effortByPhase(projectIDs: [project.id])
        XCTAssertEqual(efforts.count, 1)
        let effort = efforts.first!
        XCTAssertEqual(effort.totalActiveSeconds, 6000, accuracy: 0.001)
        XCTAssertEqual(effort.slices.reduce(0) { $0 + $1.fraction }, 1.0, accuracy: 0.001)
        XCTAssertEqual(effort.slices.first { $0.type == .drafting }?.fraction ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(effort.slices.first { $0.type == .editing }?.fraction ?? 0, 0.4, accuracy: 0.001)
    }

    func testEffortByPhaseMultipleProjectsAndUnknownType() throws {
        let a = Project(title: "A")
        let b = Project(title: "B")
        try ProjectRepository(database: database).insert(a)
        try ProjectRepository(database: database).insert(b)
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 10, type: .unknown, projectID: a.id)
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 10, type: .research, projectID: b.id)
        let efforts = analytics().effortByPhase(projectIDs: [a.id, b.id])
        XCTAssertEqual(efforts.count, 2)
        XCTAssertEqual(efforts.first { $0.projectID == a.id }?.slices.first?.type, .unknown)
    }

    func testEffortByPhaseEmptyForNoActivity() throws {
        let project = Project(title: "Idle")
        try ProjectRepository(database: database).insert(project)
        XCTAssertTrue(analytics().effortByPhase(projectIDs: [project.id]).isEmpty)
    }

    // MARK: 8. Cumulative lifetime output

    func testCumulativeLifetimeOutputAllowsNegativeNet() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: 500)
        try insertSession(start: dayAt(1, hour: 9), durationMinutes: 30, words: -200)
        try buildAggregates()
        let points = analytics().cumulativeLifetimeOutput(metric: .netWords)
        XCTAssertEqual(points.first?.value, 500)
        XCTAssertEqual(points.last?.value, 300)
        XCTAssertTrue(points.contains { $0.value < 500 })
    }

    func testCumulativeLifetimeOutputGrossDiffersFromNet() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 30, words: -100, added: 400, removed: 500)
        try buildAggregates()
        let service = analytics()
        let net = service.cumulativeLifetimeOutput(metric: .netWords).last?.value
        let gross = service.cumulativeLifetimeOutput(metric: .grossWorked).last?.value
        XCTAssertEqual(net, -100)
        XCTAssertEqual(gross, 900)
    }

    // MARK: 9. Productivity variability

    func testVariabilityConstantOutputIsZero() throws {
        for offset in 0..<7 {
            try insertSession(start: dayAt(offset, hour: 9), durationMinutes: 30, words: 100)
        }
        try buildAggregates()
        let variability = analytics().outputVariability(window: 7, range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(8, hour: 0)))
        XCTAssertEqual(variability.points.count, 1)
        XCTAssertEqual(variability.points.first?.standardDeviation ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(variability.points.first?.coefficientOfVariation ?? -1, 0, accuracy: 0.001)
    }

    func testVariabilityHighlyVariableOutput() throws {
        let values = [100, 100, 100, 100, 100, 100, 800]
        for (offset, value) in values.enumerated() {
            try insertSession(start: dayAt(offset, hour: 9), durationMinutes: 30, words: value)
        }
        try buildAggregates()
        let variability = analytics().outputVariability(window: 7, range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(8, hour: 0)))
        XCTAssertEqual(variability.points.count, 1)
        XCTAssertGreaterThan(variability.points.first?.coefficientOfVariation ?? 0, 0.5)
    }

    func testVariabilityZeroMeanHasNoCoefficientOfVariation() throws {
        let values = [100, -100, 100, -100, 100, -100, 0]
        for (offset, value) in values.enumerated() {
            try insertSession(start: dayAt(offset, hour: 9), durationMinutes: 30, words: value)
        }
        try buildAggregates()
        let variability = analytics().outputVariability(window: 7, range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(8, hour: 0)))
        XCTAssertEqual(variability.points.count, 1)
        XCTAssertNil(variability.points.first?.coefficientOfVariation)
    }

    func testVariabilityInsufficientWindow() throws {
        for offset in 0..<3 {
            try insertSession(start: dayAt(offset, hour: 9), durationMinutes: 30, words: 100)
        }
        try buildAggregates()
        let variability = analytics().outputVariability(window: 7, range: DateInterval(start: dayAt(0, hour: 0), end: dayAt(8, hour: 0)))
        XCTAssertTrue(variability.isEmpty)
    }

    // MARK: 10. Productivity by work type

    func testProductivityByWorkTypeGroupsAndUsesMedian() throws {
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, activeMinutes: 60, words: 120, type: .drafting)
        }
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, activeMinutes: 60, words: 60, type: .editing)
        }
        let items = analytics().productivityByWorkType()
        let drafting = items.first { $0.type == .drafting }
        let editing = items.first { $0.type == .editing }
        XCTAssertEqual(drafting?.medianWordsPerHour ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(editing?.medianWordsPerHour ?? 0, 60, accuracy: 0.001)
    }

    func testProductivityByWorkTypeInsufficientSamples() throws {
        try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, words: 120, type: .drafting)
        let items = analytics().productivityByWorkType()
        let drafting = items.first { $0.type == .drafting }
        XCTAssertFalse(drafting?.isSufficient ?? true)
        XCTAssertNil(drafting?.medianWordsPerHour)
    }

    func testProductivityByWorkTypeResearchWithZeroGrowth() throws {
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, activeMinutes: 60, words: 0, type: .research)
        }
        let items = analytics().productivityByWorkType()
        let research = items.first { $0.type == .research }
        XCTAssertTrue(research?.isSufficient ?? false)
        XCTAssertEqual(research?.medianWordsPerHour ?? -1, 0, accuracy: 0.001)
    }

    func testProductivityByWorkTypeIgnoresZeroActiveTime() throws {
        for _ in 0..<3 {
            try insertSession(start: dayAt(0, hour: 9), durationMinutes: 60, activeMinutes: 0, words: 120, type: .drafting)
        }
        let items = analytics().productivityByWorkType()
        let drafting = items.first { $0.type == .drafting }
        XCTAssertFalse(drafting?.isSufficient ?? true)
    }
}
