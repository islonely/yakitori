import XCTest
@testable import WritingTrackerCore

final class ProjectServiceTests: XCTestCase {
    private var database: SQLiteDatabase!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testCreateProjectAndDefaultMilestones() throws {
        let service = ProjectService(database: database)
        let project = try service.createProject(title: "Naphtali", targetWordCount: 80_000)
        let milestones = try service.milestones(forProject: project.id)
        XCTAssertEqual(milestones.count, 4)
        XCTAssertEqual(try ProjectRepository(database: database).count(), 1)
    }

    func testEvaluateMilestonesCompletesWhenTargetReached() throws {
        let service = ProjectService(database: database)
        let project = try service.createProject(title: "Novel", targetWordCount: 100_000)
        try service.evaluateMilestones(projectID: project.id, currentWordCount: 30_000)
        let milestones = try service.milestones(forProject: project.id)
        let completed = milestones.filter(\.isCompleted)
        XCTAssertEqual(completed.count, 1) // 25,000 milestone
    }

    func testProjectStatusTransitionsSetTimestamps() throws {
        let service = ProjectService(database: database)
        var project = try service.createProject(title: "Novel")
        project.status = .complete
        try service.update(project)
        let reloaded = try service.project(id: project.id)
        XCTAssertNotNil(reloaded?.completedAt)
    }

    func testAssociationRulesPriority() throws {
        let service = ProjectService(database: database)
        let project = try service.createProject(title: "Fiction")
        try service.addRule(projectID: project.id, type: .folderPath, value: "/Users/writer/Books/Fiction/")

        let resolver = ProjectAssociationService(database: database)
        let resolved = resolver.resolveProjectID(
            documentPath: "/Users/writer/Books/Fiction/chapter1.docx",
            documentName: "chapter1.docx",
            applicationID: nil
        )
        XCTAssertEqual(resolved, project.id)
    }

    func testExplicitDocumentAssociationBeatsRules() throws {
        let service = ProjectService(database: database)
        let projectA = try service.createProject(title: "A")
        let projectB = try service.createProject(title: "B")
        try service.addRule(projectID: projectA.id, type: .folderPath, value: "/Books/")

        let document = Document(projectID: projectB.id, displayName: "draft.docx", filePath: "/Books/draft.docx")
        try DocumentRepository(database: database).insert(document)

        let resolver = ProjectAssociationService(database: database)
        let resolved = resolver.resolveProjectID(documentPath: "/Books/draft.docx", documentName: "draft.docx", applicationID: nil)
        XCTAssertEqual(resolved, projectB.id)
    }
}

final class ProjectAssociationPolicyTests: XCTestCase {
    func testManualChoiceWins() {
        let result = ProjectResolution.effectiveProjectID(
            documentProjectID: "doc", resolvedProjectID: "rule",
            currentProjectID: "current", isManual: true, manualProjectID: "manual"
        )
        XCTAssertEqual(result, "manual")
    }

    func testDocumentAssociationBeatsCurrentProject() {
        let result = ProjectResolution.effectiveProjectID(
            documentProjectID: "doc", resolvedProjectID: "rule",
            currentProjectID: "current", isManual: false, manualProjectID: nil
        )
        XCTAssertEqual(result, "doc")
    }

    func testCurrentProjectFallbackWhenNoAssociation() {
        let result = ProjectResolution.effectiveProjectID(
            documentProjectID: nil, resolvedProjectID: nil,
            currentProjectID: "current", isManual: false, manualProjectID: nil
        )
        XCTAssertEqual(result, "current")
    }

    func testNilWhenNothingMatches() {
        let result = ProjectResolution.effectiveProjectID(
            documentProjectID: nil, resolvedProjectID: nil,
            currentProjectID: nil, isManual: false, manualProjectID: nil
        )
        XCTAssertNil(result)
    }
}

final class SessionServiceTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var statistics: StatisticsService!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        statistics = StatisticsService(
            database: database,
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T21:00:00-04:00")),
            calendarContext: TestSupport.calendar()
        )
    }

    override func tearDown() {
        database = nil
        statistics = nil
        super.tearDown()
    }

    func testManualSessionEntryCreatesAggregate() throws {
        let service = SessionService(database: database, statistics: statistics)
        let project = try ProjectService(database: database).createProject(title: "Paper Project")
        let date = TestSupport.date("2026-09-08T09:00:00-04:00")
        try service.addManualSession(projectID: project.id, date: date, words: 1500, activeSeconds: 7200, sessionType: .drafting)

        let aggregates = try DailyAggregateRepository(database: database).all()
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates.first?.netWords, 1500)
        XCTAssertEqual(aggregates.first?.activeSeconds ?? 0, 7200, accuracy: 0.001)
    }

    func testCorrectDurationRebuildsAggregates() throws {
        let service = SessionService(database: database, statistics: statistics)
        let date = TestSupport.date("2026-09-08T09:00:00-04:00")
        let session = try service.addManualSession(projectID: nil, date: date, words: 100, activeSeconds: 3600)
        try service.correctDuration(sessionID: session.id, activeSeconds: 1800)
        let aggregate = try DailyAggregateRepository(database: database).find(dayKey: "2026-09-08")
        XCTAssertEqual(aggregate?.activeSeconds ?? 0, 1800, accuracy: 0.001)
    }

    func testSessionNotesAndTypeUpdates() throws {
        let service = SessionService(database: database, statistics: statistics)
        let date = TestSupport.date("2026-09-08T09:00:00-04:00")
        let session = try service.addManualSession(projectID: nil, date: date, words: 100, activeSeconds: 600)
        try service.setNotes(sessionID: session.id, notes: "Finished Chapter 23.")
        try service.setSessionType(sessionID: session.id, type: .editing)
        let updated = try service.session(id: session.id)
        XCTAssertEqual(updated?.notes, "Finished Chapter 23.")
        XCTAssertEqual(updated?.sessionType, .editing)
    }
}

final class ExportAndBackupTests: XCTestCase {
    private var directory: URL!
    private var database: SQLiteDatabase!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("wt-services-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: directory.appendingPathComponent("test.sqlite").path)
        try Migrator(database: database).migrate()
    }

    override func tearDown() {
        database?.close()
        database = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeStatistics() -> StatisticsService {
        StatisticsService(database: database, dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T21:00:00-04:00")), calendarContext: TestSupport.calendar())
    }

    func testJSONExportRoundTrips() throws {
        let project = TestSupport.makeProject(title: "Exported")
        try ProjectRepository(database: database).insert(project)
        let statistics = makeStatistics()
        let service = ExportService(database: database, statistics: statistics)

        let result = try service.export(scope: .all, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: result.data)
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertEqual(document.projects.first?.title, "Exported")
        // Privacy: JSON must never contain a manuscript text field.
        let text = String(data: result.data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("manuscriptText"))
    }

    func testCSVExportsSessions() throws {
        let statistics = makeStatistics()
        try SessionService(database: database, statistics: statistics).addManualSession(
            projectID: nil, date: TestSupport.date("2026-09-08T09:00:00-04:00"), words: 500, activeSeconds: 1800
        )
        let service = ExportService(database: database, statistics: statistics)
        let result = try service.export(scope: .sessions, format: .csv)
        let text = String(data: result.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("started_at"))
        XCTAssertTrue(text.contains("drafting"))
    }

    func testBackupCreatesReadableFile() throws {
        try ProjectRepository(database: database).insert(TestSupport.makeProject(title: "Backed Up"))
        let backupsDir = directory.appendingPathComponent("Backups")
        let service = BackupService(
            database: database,
            databaseURL: directory.appendingPathComponent("test.sqlite"),
            backupsDirectory: backupsDir,
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00"))
        )
        let url = try service.createBackup(label: "test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let backupDB = try SQLiteDatabase(path: url.path)
        XCTAssertEqual(try ProjectRepository(database: backupDB).all().first?.title, "Backed Up")
        backupDB.close()
        XCTAssertEqual(service.listBackups().count, 1)
    }

    func testDestructiveOperationCreatesBackupFirst() throws {
        let statistics = makeStatistics()
        try ProjectRepository(database: database).insert(TestSupport.makeProject(title: "Keep"))
        try SessionRepository(database: database).insert(Session(startedAt: Date(), endedAt: Date(), activeSeconds: 60, netWordChange: 100))

        let backupService = BackupService(
            database: database,
            databaseURL: directory.appendingPathComponent("test.sqlite"),
            backupsDirectory: directory.appendingPathComponent("Backups"),
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00"))
        )
        let management = DataManagementService(database: database, backupService: backupService, statistics: statistics)

        let backupURL = try management.deleteSessionHistory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try SessionRepository(database: database).count(), 0)
        // The project survives a session-history delete.
        XCTAssertEqual(try ProjectRepository(database: database).count(), 1)
    }

    func testFactoryResetClearsEverythingAfterBackup() throws {
        let statistics = makeStatistics()
        try ProjectRepository(database: database).insert(TestSupport.makeProject(title: "Gone"))
        let backupService = BackupService(
            database: database,
            databaseURL: directory.appendingPathComponent("test.sqlite"),
            backupsDirectory: directory.appendingPathComponent("Backups"),
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00"))
        )
        let management = DataManagementService(database: database, backupService: backupService, statistics: statistics)
        _ = try management.factoryReset()
        XCTAssertEqual(try ProjectRepository(database: database).count(), 0)
    }
}

final class ReportServiceTests: XCTestCase {
    private var database: SQLiteDatabase!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testAchievementsAndComparisons() throws {
        let statistics = StatisticsService(
            database: database,
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T21:00:00-04:00")),
            calendarContext: TestSupport.calendar()
        )
        try SessionRepository(database: database).insert(
            Session(startedAt: TestSupport.date("2026-09-08T09:00:00-04:00"),
                    endedAt: TestSupport.date("2026-09-08T10:00:00-04:00"),
                    activeSeconds: 3600, endingWordCount: 1500, netWordChange: 1500)
        )
        try TestSupport.buildAggregates(database, calendar: TestSupport.calendar())

        let service = ReportService(statistics: statistics, dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T21:00:00-04:00")), calendarContext: TestSupport.calendar())
        let achievements = service.achievements()
        XCTAssertEqual(achievements.count, 8)
        XCTAssertTrue(achievements.first(where: { $0.id == "first1k" })?.isUnlocked ?? false)

        let yearly = service.yearlyReport(year: 2026)
        XCTAssertEqual(yearly.period.netWords, 1500)
        let review = service.yearInReview(year: 2026)
        XCTAssertFalse(review.highlights.isEmpty)
    }
}
