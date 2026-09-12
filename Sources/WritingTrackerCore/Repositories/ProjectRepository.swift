import Foundation

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

public final class ProjectRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ project: Project) throws {
        try database.execute("""
        INSERT INTO projects (id, title, type, description, status, target_word_count,
            starting_word_count, current_word_count, deadline, created_at, started_at,
            completed_at, archived_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, [
            .text(project.id), .text(project.title), .text(project.type.rawValue),
            project.description.map { .text($0) } ?? .null, .text(project.status.rawValue),
            project.targetWordCount.map { .integer(Int64($0)) } ?? .null,
            .integer(Int64(project.startingWordCount)), .integer(Int64(project.currentWordCount)),
            .date(project.deadline), .date(project.createdAt), .date(project.startedAt),
            .date(project.completedAt), .date(project.archivedAt)
        ])
    }

    public func update(_ project: Project) throws {
        try database.execute("""
        UPDATE projects SET title=?, type=?, description=?, status=?, target_word_count=?,
            starting_word_count=?, current_word_count=?, deadline=?, created_at=?, started_at=?,
            completed_at=?, archived_at=? WHERE id=?;
        """, [
            .text(project.title), .text(project.type.rawValue),
            project.description.map { .text($0) } ?? .null, .text(project.status.rawValue),
            project.targetWordCount.map { .integer(Int64($0)) } ?? .null,
            .integer(Int64(project.startingWordCount)), .integer(Int64(project.currentWordCount)),
            .date(project.deadline), .date(project.createdAt), .date(project.startedAt),
            .date(project.completedAt), .date(project.archivedAt), .text(project.id)
        ])
    }

    public func upsert(_ project: Project) throws {
        if try find(id: project.id) != nil { try update(project) } else { try insert(project) }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM projects WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> Project? {
        try database.queryOne("SELECT * FROM projects WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    public func all(includeArchived: Bool = true) throws -> [Project] {
        let sql = includeArchived
            ? "SELECT * FROM projects ORDER BY title COLLATE NOCASE;"
            : "SELECT * FROM projects WHERE archived_at IS NULL ORDER BY title COLLATE NOCASE;"
        return try database.query(sql).map(Self.map)
    }

    public func active() throws -> [Project] {
        try all(includeArchived: false).filter { $0.status.isActive }
    }

    public func completed() throws -> [Project] {
        try all().filter { $0.status.isCompleted }
    }

    public func count() throws -> Int {
        try database.scalar("SELECT COUNT(*) FROM projects;")?.intValue ?? 0
    }

    public func updateCurrentWordCount(id: String, wordCount: Int) throws {
        try database.execute(
            "UPDATE projects SET current_word_count = ? WHERE id = ?;",
            [.integer(Int64(wordCount)), .text(id)]
        )
    }

    public func findByTitle(_ title: String) throws -> Project? {
        try database.queryOne(
            "SELECT * FROM projects WHERE title = ? LIMIT 1;", [.text(title)]
        ).map(Self.map)
    }

    static func map(_ row: Row) -> Project {
        Project(
            id: row.string("id") ?? UUID().uuidString,
            title: row.string("title") ?? "Untitled",
            type: ProjectType(rawValue: row.string("type") ?? "other") ?? .other,
            description: row.string("description"),
            status: ProjectStatus(rawValue: row.string("status") ?? "idea") ?? .idea,
            targetWordCount: row.int("target_word_count"),
            startingWordCount: row.int("starting_word_count") ?? 0,
            currentWordCount: row.int("current_word_count") ?? 0,
            deadline: row.date("deadline"),
            createdAt: row.date("created_at") ?? Date(),
            startedAt: row.date("started_at"),
            completedAt: row.date("completed_at"),
            archivedAt: row.date("archived_at")
        )
    }
}
