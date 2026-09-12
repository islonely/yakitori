import Foundation

public struct SessionFilter: Hashable, Sendable {
    public var startDate: Date?
    public var endDate: Date?
    public var projectID: String?
    public var applicationID: String?
    public var sessionType: SessionType?
    public var minimumDuration: TimeInterval?
    public var minimumNetWords: Int?
    public var searchText: String?

    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        projectID: String? = nil,
        applicationID: String? = nil,
        sessionType: SessionType? = nil,
        minimumDuration: TimeInterval? = nil,
        minimumNetWords: Int? = nil,
        searchText: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.projectID = projectID
        self.applicationID = applicationID
        self.sessionType = sessionType
        self.minimumDuration = minimumDuration
        self.minimumNetWords = minimumNetWords
        self.searchText = searchText
    }
}

public final class SessionRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ session: Session) throws {
        try database.execute("""
        INSERT INTO sessions (id, project_id, document_id, application_id, started_at, ended_at,
            active_seconds, focus_seconds, starting_word_count, ending_word_count, words_added,
            words_removed, net_word_change, session_type, notes, active_ranges, focus_ranges, is_recovered)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, Self.params(session))
    }

    public func update(_ session: Session) throws {
        try database.execute("""
        UPDATE sessions SET project_id=?, document_id=?, application_id=?, started_at=?, ended_at=?,
            active_seconds=?, focus_seconds=?, starting_word_count=?, ending_word_count=?, words_added=?,
            words_removed=?, net_word_change=?, session_type=?, notes=?, active_ranges=?, focus_ranges=?,
            is_recovered=? WHERE id=?;
        """, Array(Self.params(session).dropFirst()) + [.text(session.id)])
    }

    public func upsert(_ session: Session) throws {
        if try find(id: session.id) != nil { try update(session) } else { try insert(session) }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM sessions WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> Session? {
        try database.queryOne("SELECT * FROM sessions WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    public func all() throws -> [Session] {
        try database.query("SELECT * FROM sessions ORDER BY started_at DESC;").map(Self.map)
    }

    public func completed() throws -> [Session] {
        try database.query("SELECT * FROM sessions WHERE ended_at IS NOT NULL ORDER BY started_at DESC;").map(Self.map)
    }

    public func openSessions() throws -> [Session] {
        try database.query("SELECT * FROM sessions WHERE ended_at IS NULL ORDER BY started_at;").map(Self.map)
    }

    public func sessions(in range: DateInterval) throws -> [Session] {
        try sessions(filter: SessionFilter(startDate: range.start, endDate: range.end))
    }

    public func sessions(filter: SessionFilter) throws -> [Session] {
        var clauses: [String] = []
        var params: SQLParameters = []
        if let start = filter.startDate {
            clauses.append("started_at >= ?"); params.append(.date(start))
        }
        if let end = filter.endDate {
            clauses.append("started_at < ?"); params.append(.date(end))
        }
        if let projectID = filter.projectID {
            clauses.append("project_id = ?"); params.append(.text(projectID))
        }
        if let applicationID = filter.applicationID {
            clauses.append("application_id = ?"); params.append(.text(applicationID))
        }
        if let type = filter.sessionType {
            clauses.append("session_type = ?"); params.append(.text(type.rawValue))
        }
        if let minDuration = filter.minimumDuration {
            clauses.append("(COALESCE(ended_at, started_at) - started_at) >= ?")
            params.append(.real(minDuration))
        }
        if let minNet = filter.minimumNetWords {
            clauses.append("net_word_change >= ?"); params.append(.integer(Int64(minNet)))
        }
        if let text = filter.searchText, !text.isEmpty {
            clauses.append("(COALESCE(notes,'') LIKE ? OR COALESCE(session_type,'') LIKE ?)")
            params.append(.text("%\(text)%")); params.append(.text("%\(text)%"))
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        return try database.query("SELECT * FROM sessions \(whereClause) ORDER BY started_at DESC;", params).map(Self.map)
    }

    public func sessions(forProject projectID: String) throws -> [Session] {
        try database.query(
            "SELECT * FROM sessions WHERE project_id = ? ORDER BY started_at DESC;", [.text(projectID)]
        ).map(Self.map)
    }

    public func sessions(forDocument documentID: String) throws -> [Session] {
        try database.query(
            "SELECT * FROM sessions WHERE document_id = ? ORDER BY started_at DESC;", [.text(documentID)]
        ).map(Self.map)
    }

    public func count() throws -> Int {
        try database.scalar("SELECT COUNT(*) FROM sessions;")?.intValue ?? 0
    }

    public func earliest() throws -> Session? {
        try database.queryOne("SELECT * FROM sessions ORDER BY started_at ASC LIMIT 1;").map(Self.map)
    }

    public func latest() throws -> Session? {
        try database.queryOne("SELECT * FROM sessions ORDER BY started_at DESC LIMIT 1;").map(Self.map)
    }

    public func deleteAll() throws {
        try database.execute("DELETE FROM sessions;")
    }

    private static func params(_ session: Session) -> SQLParameters {
        [
            .text(session.id),
            session.projectID.map { .text($0) } ?? .null,
            session.documentID.map { .text($0) } ?? .null,
            session.applicationID.map { .text($0) } ?? .null,
            .date(session.startedAt),
            .date(session.endedAt),
            .real(session.activeSeconds),
            .real(session.focusSeconds),
            session.startingWordCount.map { .integer(Int64($0)) } ?? .null,
            session.endingWordCount.map { .integer(Int64($0)) } ?? .null,
            session.wordsAdded.map { .integer(Int64($0)) } ?? .null,
            session.wordsRemoved.map { .integer(Int64($0)) } ?? .null,
            session.netWordChange.map { .integer(Int64($0)) } ?? .null,
            .text(session.sessionType.rawValue),
            session.notes.map { .text($0) } ?? .null,
            .text(JSONCoding.encode(session.activeRanges)),
            .text(JSONCoding.encode(session.focusRanges)),
            .bool(session.isRecovered)
        ]
    }

    static func map(_ row: Row) -> Session {
        Session(
            id: row.string("id") ?? UUID().uuidString,
            projectID: row.string("project_id"),
            documentID: row.string("document_id"),
            applicationID: row.string("application_id"),
            startedAt: row.date("started_at") ?? Date(),
            endedAt: row.date("ended_at"),
            activeSeconds: row.double("active_seconds") ?? 0,
            focusSeconds: row.double("focus_seconds") ?? 0,
            startingWordCount: row.int("starting_word_count"),
            endingWordCount: row.int("ending_word_count"),
            wordsAdded: row.int("words_added"),
            wordsRemoved: row.int("words_removed"),
            netWordChange: row.int("net_word_change"),
            sessionType: SessionType(rawValue: row.string("session_type") ?? "unknown") ?? .unknown,
            notes: row.string("notes"),
            activeRanges: JSONCoding.decode([TimeRange].self, from: row.string("active_ranges")) ?? [],
            focusRanges: JSONCoding.decode([TimeRange].self, from: row.string("focus_ranges")) ?? [],
            isRecovered: row.bool("is_recovered") ?? false
        )
    }
}
