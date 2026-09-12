import Foundation
import XCTest
@testable import WritingTrackerCore

enum TestSupport {
    static func makeDatabase() throws -> SQLiteDatabase {
        let db = try SQLiteDatabase.inMemory()
        try Migrator(database: db).migrate()
        return db
    }

    static func calendar(_ timeZoneID: String = "America/New_York", firstWeekday: WeekStart = .sunday) -> CalendarContext {
        CalendarContext(timeZone: TimeZone(identifier: timeZoneID)!, firstWeekday: firstWeekday)
    }

    static func date(_ iso: String, timeZoneID: String = "America/New_York") -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: timeZoneID)!
        return formatter.date(from: iso)!
    }

    static func makeProject(title: String = "Test Project", target: Int? = 80_000, current: Int = 0) -> Project {
        Project(title: title, type: .novel, status: .drafting, targetWordCount: target, currentWordCount: current)
    }

    @discardableResult
    static func insertSessions(_ sessions: [Session], into database: Database) throws -> [Session] {
        let repo = SessionRepository(database: database)
        for session in sessions { try repo.insert(session) }
        return sessions
    }

    static func buildAggregates(_ database: Database, calendar: CalendarContext) throws {
        let sessions = try SessionRepository(database: database).all()
        let aggregates = DailyAggregateBuilder(calendar: calendar).aggregates(for: sessions)
        try DailyAggregateRepository(database: database).replaceAll(aggregates)
    }
}

final class InMemoryDatabaseTests: XCTestCase {
    func testMigrationsApplyCleanlyAndAreIdempotent() throws {
        let db = try SQLiteDatabase.inMemory()
        let migrator = Migrator(database: db)
        let version = try migrator.migrate()
        XCTAssertEqual(version, 1)
        XCTAssertEqual(migrator.currentVersion, 1)
        // Running again must not throw or change the version.
        XCTAssertEqual(try migrator.migrate(), 1)
    }

    func testDatabasePersistsAcrossConnections() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wt-persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.sqlite").path

        do {
            let db = try SQLiteDatabase(path: path)
            try Migrator(database: db).migrate()
            try ProjectRepository(database: db).insert(TestSupport.makeProject(title: "Persisted"))
            db.close()
        }

        let reopened = try SQLiteDatabase(path: path)
        let projects = try ProjectRepository(database: reopened).all()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.title, "Persisted")
        reopened.close()
    }
}
