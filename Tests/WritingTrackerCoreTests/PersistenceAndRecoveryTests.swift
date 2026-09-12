import XCTest
@testable import WritingTrackerCore

final class PersistenceAndRecoveryTests: XCTestCase {
    private var database: SQLiteDatabase!
    private let calendar = TestSupport.calendar("America/New_York")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testProjectCRUD() throws {
        let repo = ProjectRepository(database: database)
        var project = TestSupport.makeProject(title: "Novel X")
        try repo.insert(project)
        XCTAssertEqual(try repo.count(), 1)

        project.currentWordCount = 1234
        try repo.update(project)
        XCTAssertEqual(try repo.find(id: project.id)?.currentWordCount, 1234)

        let found = try repo.findByTitle("Novel X")
        XCTAssertEqual(found?.id, project.id)
    }

    func testDocumentIdentityPriority() throws {
        let repo = DocumentRepository(database: database)
        let stable = Document(displayName: "Draft", stableIdentifier: "/tmp/draft.docx", filePath: "/tmp/draft.docx")
        try repo.insert(stable)

        // Lookup by stable identifier wins.
        XCTAssertEqual(try repo.find(stableIdentifier: "/tmp/draft.docx")?.id, stable.id)
        XCTAssertEqual(try repo.find(filePath: "/tmp/draft.docx")?.id, stable.id)
    }

    func testSessionFiltering() throws {
        let start = TestSupport.date("2026-09-08T09:00:00-04:00")
        let repo = SessionRepository(database: database)
        let s1 = Session(startedAt: start, endedAt: start.addingTimeInterval(3600), activeSeconds: 3600, netWordChange: 500, sessionType: .drafting)
        let s2 = Session(startedAt: start.addingTimeInterval(7200), endedAt: start.addingTimeInterval(10_800), activeSeconds: 3600, netWordChange: 0, sessionType: .editing)
        try repo.insert(s1)
        try repo.insert(s2)

        let drafting = try repo.sessions(filter: SessionFilter(sessionType: .drafting))
        XCTAssertEqual(drafting.map(\.id), [s1.id])
        let wordy = try repo.sessions(filter: SessionFilter(minimumNetWords: 100))
        XCTAssertEqual(wordy.map(\.id), [s1.id])
    }

    func testCrashRecoveryDoesNotCountTimeWhileNotRunning() throws {
        let start = TestSupport.date("2026-09-08T10:00:00-04:00")
        let lastCheckpoint = start.addingTimeInterval(47 * 60)
        let open = Session(
            startedAt: start,
            endedAt: nil,
            activeSeconds: 47 * 60,
            focusSeconds: 47 * 60,
            activeRanges: [TimeRange(start: start, end: lastCheckpoint)],
            focusRanges: [TimeRange(start: start, end: lastCheckpoint)]
        )
        try SessionRepository(database: database).insert(open)

        // The app "restarts" two hours later.
        let restart = start.addingTimeInterval(2 * 3600)
        let engine = TrackingEngine(
            database: database,
            permissionProvider: MockPermissionManager(),
            dateProvider: MutableDateProvider(restart),
            calendarContext: calendar
        )
        engine.recoverOpenSessions()

        let recovered = try SessionRepository(database: database).find(id: open.id)
        XCTAssertNotNil(recovered?.endedAt)
        XCTAssertTrue(recovered?.isRecovered ?? false)
        // Ends at the last checkpoint (10:47), NOT at the restart time (12:00).
        XCTAssertEqual(recovered?.endedAt?.timeIntervalSince1970 ?? 0, lastCheckpoint.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(recovered?.activeSeconds ?? 0, 47 * 60, accuracy: 1)
    }

    func testRebuildAggregatesFromSessions() throws {
        let start = TestSupport.date("2026-09-08T09:00:00-04:00")
        let session = Session(
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            activeSeconds: 1800,
            focusSeconds: 1800,
            netWordChange: 400,
            activeRanges: [TimeRange(start: start, end: start.addingTimeInterval(1800))]
        )
        try SessionRepository(database: database).insert(session)
        let service = StatisticsService(database: database, dateProvider: MutableDateProvider(start), calendarContext: calendar)
        XCTAssertEqual(service.rebuildDailyAggregates(), 1)
        XCTAssertEqual(service.dailyStatistics(date: start).netWords, 400)
    }

    func testSettingsRoundTrip() throws {
        let repo = SettingsRepository(database: database)
        var settings = UserSettings.default
        settings.trackingMode = .automaticFiltered
        settings.inactivityTimeout = .tenMinutes
        settings.streakThresholdKind = .words250
        settings.selectedApplicationIDs = ["a", "b"]
        try repo.save(settings)
        let loaded = try repo.load()
        XCTAssertEqual(loaded.trackingMode, .automaticFiltered)
        XCTAssertEqual(loaded.inactivityTimeout, .tenMinutes)
        XCTAssertEqual(loaded.streakThresholdKind, .words250)
        XCTAssertEqual(loaded.selectedApplicationIDs, ["a", "b"])
    }

    func testCascadeDeleteRemovesGoalsAndMilestones() throws {
        let project = TestSupport.makeProject()
        try ProjectRepository(database: database).insert(project)
        try GoalRepository(database: database).insert(Goal(projectID: project.id, period: .project, target: 1000))
        try MilestoneRepository(database: database).insert(Milestone(projectID: project.id, title: "Draft"))
        try ProjectRepository(database: database).delete(id: project.id)
        XCTAssertTrue(try GoalRepository(database: database).goals(forProject: project.id).isEmpty)
        XCTAssertTrue(try MilestoneRepository(database: database).milestones(forProject: project.id).isEmpty)
    }
}
