import Foundation

public final class DocumentRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ document: Document) throws {
        try database.execute("""
        INSERT INTO documents (id, project_id, application_id, display_name, stable_identifier,
            file_path, created_at, last_seen_at)
        VALUES (?,?,?,?,?,?,?,?);
        """, [
            .text(document.id), document.projectID.map { .text($0) } ?? .null,
            document.applicationID.map { .text($0) } ?? .null, .text(document.displayName),
            document.stableIdentifier.map { .text($0) } ?? .null,
            document.filePath.map { .text($0) } ?? .null,
            .date(document.createdAt), .date(document.lastSeenAt)
        ])
    }

    public func update(_ document: Document) throws {
        try database.execute("""
        UPDATE documents SET project_id=?, application_id=?, display_name=?, stable_identifier=?,
            file_path=?, created_at=?, last_seen_at=? WHERE id=?;
        """, [
            document.projectID.map { .text($0) } ?? .null,
            document.applicationID.map { .text($0) } ?? .null, .text(document.displayName),
            document.stableIdentifier.map { .text($0) } ?? .null,
            document.filePath.map { .text($0) } ?? .null,
            .date(document.createdAt), .date(document.lastSeenAt), .text(document.id)
        ])
    }

    public func upsert(_ document: Document) throws {
        if try find(id: document.id) != nil { try update(document) } else { try insert(document) }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM documents WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> Document? {
        try database.queryOne("SELECT * FROM documents WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    /// Document identity resolution in priority order.
    public func find(stableIdentifier: String) throws -> Document? {
        try database.queryOne(
            "SELECT * FROM documents WHERE stable_identifier = ? LIMIT 1;", [.text(stableIdentifier)]
        ).map(Self.map)
    }

    public func find(filePath: String) throws -> Document? {
        try database.queryOne(
            "SELECT * FROM documents WHERE file_path = ? LIMIT 1;", [.text(filePath)]
        ).map(Self.map)
    }

    public func find(displayName: String, applicationID: String?) throws -> Document? {
        if let applicationID {
            return try database.queryOne(
                "SELECT * FROM documents WHERE display_name = ? AND application_id = ? ORDER BY last_seen_at DESC LIMIT 1;",
                [.text(displayName), .text(applicationID)]
            ).map(Self.map)
        }
        return try database.queryOne(
            "SELECT * FROM documents WHERE display_name = ? ORDER BY last_seen_at DESC LIMIT 1;",
            [.text(displayName)]
        ).map(Self.map)
    }

    public func all() throws -> [Document] {
        try database.query("SELECT * FROM documents ORDER BY last_seen_at DESC;").map(Self.map)
    }

    public func documents(forProject projectID: String) throws -> [Document] {
        try database.query(
            "SELECT * FROM documents WHERE project_id = ? ORDER BY last_seen_at DESC;",
            [.text(projectID)]
        ).map(Self.map)
    }

    public func touch(id: String, at date: Date) throws {
        try database.execute(
            "UPDATE documents SET last_seen_at = ? WHERE id = ?;", [.date(date), .text(id)]
        )
    }

    public func assignProject(documentID: String, projectID: String?) throws {
        try database.execute(
            "UPDATE documents SET project_id = ? WHERE id = ?;",
            [projectID.map { .text($0) } ?? .null, .text(documentID)]
        )
    }

    public func deleteOrphans() throws {
        try database.execute("DELETE FROM documents WHERE id NOT IN (SELECT DISTINCT document_id FROM sessions WHERE document_id IS NOT NULL);")
    }

    static func map(_ row: Row) -> Document {
        Document(
            id: row.string("id") ?? UUID().uuidString,
            projectID: row.string("project_id"),
            applicationID: row.string("application_id"),
            displayName: row.string("display_name") ?? "Untitled",
            stableIdentifier: row.string("stable_identifier"),
            filePath: row.string("file_path"),
            createdAt: row.date("created_at") ?? Date(),
            lastSeenAt: row.date("last_seen_at") ?? Date()
        )
    }
}
