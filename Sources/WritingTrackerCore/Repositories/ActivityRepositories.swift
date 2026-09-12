import Foundation

public final class ActivityEventRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ event: ActivityEvent) throws {
        try database.execute("""
        INSERT INTO activity_events (id, timestamp, application_id, event_type, session_id, metadata)
        VALUES (?,?,?,?,?,?);
        """, [
            .text(event.id), .date(event.timestamp),
            event.applicationID.map { .text($0) } ?? .null,
            .text(event.eventType.rawValue),
            event.sessionID.map { .text($0) } ?? .null,
            .text(JSONCoding.encode(event.metadata))
        ])
    }

    public func insertBatch(_ events: [ActivityEvent]) throws {
        guard !events.isEmpty else { return }
        try database.transaction {
            for event in events { try insert(event) }
        }
    }

    public func events(in range: DateInterval) throws -> [ActivityEvent] {
        try database.query(
            "SELECT * FROM activity_events WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp;",
            [.date(range.start), .date(range.end)]
        ).map(Self.map)
    }

    public func events(forSession sessionID: String) throws -> [ActivityEvent] {
        try database.query(
            "SELECT * FROM activity_events WHERE session_id = ? ORDER BY timestamp;",
            [.text(sessionID)]
        ).map(Self.map)
    }

    public func count() throws -> Int {
        try database.scalar("SELECT COUNT(*) FROM activity_events;")?.intValue ?? 0
    }

    public func deleteAll() throws { try database.execute("DELETE FROM activity_events;") }

    public func prune(before date: Date) throws {
        try database.execute("DELETE FROM activity_events WHERE timestamp < ?;", [.date(date)])
    }

    static func map(_ row: Row) -> ActivityEvent {
        ActivityEvent(
            id: row.string("id") ?? UUID().uuidString,
            timestamp: row.date("timestamp") ?? Date(),
            applicationID: row.string("application_id"),
            eventType: ActivityEventType(rawValue: row.string("event_type") ?? "") ?? .keyboardActivity,
            sessionID: row.string("session_id"),
            metadata: JSONCoding.decode([String: String].self, from: row.string("metadata")) ?? [:]
        )
    }
}

public final class WordCountSnapshotRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ snapshot: WordCountSnapshot) throws {
        try database.execute("""
        INSERT INTO word_count_snapshots (id, timestamp, document_id, project_id, word_count,
            character_count, page_count, source)
        VALUES (?,?,?,?,?,?,?,?);
        """, [
            .text(snapshot.id), .date(snapshot.timestamp),
            snapshot.documentID.map { .text($0) } ?? .null,
            snapshot.projectID.map { .text($0) } ?? .null,
            .integer(Int64(snapshot.wordCount)),
            snapshot.characterCount.map { .integer(Int64($0)) } ?? .null,
            snapshot.pageCount.map { .integer(Int64($0)) } ?? .null,
            .text(snapshot.source)
        ])
    }

    public func snapshots(forDocument documentID: String) throws -> [WordCountSnapshot] {
        try database.query(
            "SELECT * FROM word_count_snapshots WHERE document_id = ? ORDER BY timestamp;",
            [.text(documentID)]
        ).map(Self.map)
    }

    public func snapshots(forProject projectID: String) throws -> [WordCountSnapshot] {
        try database.query(
            "SELECT * FROM word_count_snapshots WHERE project_id = ? ORDER BY timestamp;",
            [.text(projectID)]
        ).map(Self.map)
    }

    public func snapshots(in range: DateInterval) throws -> [WordCountSnapshot] {
        try database.query(
            "SELECT * FROM word_count_snapshots WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp;",
            [.date(range.start), .date(range.end)]
        ).map(Self.map)
    }

    public func latest(forDocument documentID: String) throws -> WordCountSnapshot? {
        try database.queryOne(
            "SELECT * FROM word_count_snapshots WHERE document_id = ? ORDER BY timestamp DESC LIMIT 1;",
            [.text(documentID)]
        ).map(Self.map)
    }

    public func all() throws -> [WordCountSnapshot] {
        try database.query("SELECT * FROM word_count_snapshots ORDER BY timestamp;").map(Self.map)
    }

    public func deleteAll() throws { try database.execute("DELETE FROM word_count_snapshots;") }

    static func map(_ row: Row) -> WordCountSnapshot {
        WordCountSnapshot(
            id: row.string("id") ?? UUID().uuidString,
            timestamp: row.date("timestamp") ?? Date(),
            documentID: row.string("document_id"),
            projectID: row.string("project_id"),
            wordCount: row.int("word_count") ?? 0,
            characterCount: row.int("character_count"),
            pageCount: row.int("page_count"),
            source: row.string("source") ?? "unknown"
        )
    }
}
