import Foundation

public final class WritingApplicationRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ app: WritingApplication) throws {
        try database.execute("""
        INSERT INTO writing_applications (id, bundle_identifier, display_name, icon_reference,
            adapter_type, category, enabled, automatic_tracking_enabled, configuration, created_at, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?);
        """, Self.params(app))
    }

    public func update(_ app: WritingApplication) throws {
        try database.execute("""
        UPDATE writing_applications SET bundle_identifier=?, display_name=?, icon_reference=?,
            adapter_type=?, category=?, enabled=?, automatic_tracking_enabled=?, configuration=?,
            created_at=?, updated_at=? WHERE id=?;
        """, Array(Self.params(app).dropFirst()) + [.text(app.id)])
    }

    public func upsert(_ app: WritingApplication) throws {
        if let existing = try find(bundleIdentifier: app.bundleIdentifier) {
            var merged = app
            merged.id = existing.id
            merged.createdAt = existing.createdAt
            try update(merged)
        } else {
            try insert(app)
        }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM writing_applications WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> WritingApplication? {
        try database.queryOne("SELECT * FROM writing_applications WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    public func find(bundleIdentifier: String) throws -> WritingApplication? {
        try database.queryOne(
            "SELECT * FROM writing_applications WHERE bundle_identifier = ?;", [.text(bundleIdentifier)]
        ).map(Self.map)
    }

    public func all() throws -> [WritingApplication] {
        try database.query("SELECT * FROM writing_applications ORDER BY display_name COLLATE NOCASE;").map(Self.map)
    }

    public func enabled() throws -> [WritingApplication] {
        try database.query("SELECT * FROM writing_applications WHERE enabled = 1;").map(Self.map)
    }

    public func count() throws -> Int {
        try database.scalar("SELECT COUNT(*) FROM writing_applications;")?.intValue ?? 0
    }

    private static func params(_ app: WritingApplication) -> SQLParameters {
        [
            .text(app.id), .text(app.bundleIdentifier), .text(app.displayName),
            app.iconReference.map { .text($0) } ?? .null,
            .text(app.adapterType.rawValue), .text(app.category.rawValue),
            .bool(app.enabled), .bool(app.automaticTrackingEnabled),
            .text(JSONCoding.encode(app.configuration)), .date(app.createdAt), .date(app.updatedAt)
        ]
    }

    static func map(_ row: Row) -> WritingApplication {
        WritingApplication(
            id: row.string("id") ?? UUID().uuidString,
            bundleIdentifier: row.string("bundle_identifier") ?? "",
            displayName: row.string("display_name") ?? "",
            iconReference: row.string("icon_reference"),
            adapterType: AdapterType(rawValue: row.string("adapter_type") ?? "generic") ?? .generic,
            category: ApplicationCategory(rawValue: row.string("category") ?? "writing") ?? .writing,
            enabled: row.bool("enabled") ?? true,
            automaticTrackingEnabled: row.bool("automatic_tracking_enabled") ?? true,
            configuration: JSONCoding.decode([String: String].self, from: row.string("configuration")) ?? [:],
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date()
        )
    }
}

public final class AssociationRuleRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ rule: AssociationRule) throws {
        try database.execute("""
        INSERT INTO association_rules (id, project_id, type, value, created_at) VALUES (?,?,?,?,?);
        """, [.text(rule.id), .text(rule.projectID), .text(rule.type.rawValue), .text(rule.value), .date(rule.createdAt)])
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM association_rules WHERE id = ?;", [.text(id)])
    }

    public func all() throws -> [AssociationRule] {
        try database.query("SELECT * FROM association_rules ORDER BY created_at;").map(Self.map)
    }

    public func rules(forProject projectID: String) throws -> [AssociationRule] {
        try database.query("SELECT * FROM association_rules WHERE project_id = ?;", [.text(projectID)]).map(Self.map)
    }

    static func map(_ row: Row) -> AssociationRule {
        AssociationRule(
            id: row.string("id") ?? UUID().uuidString,
            projectID: row.string("project_id") ?? "",
            type: AssociationRule.RuleType(rawValue: row.string("type") ?? "folderPath") ?? .folderPath,
            value: row.string("value") ?? "",
            createdAt: row.date("created_at") ?? Date()
        )
    }
}

public final class SettingsRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func load() throws -> UserSettings {
        guard let row = try database.queryOne("SELECT json FROM user_settings WHERE id = 1;"),
              let settings = JSONCoding.decode(UserSettings.self, from: row.string("json")) else {
            return .default
        }
        return settings
    }

    public func save(_ settings: UserSettings) throws {
        try database.execute("""
        INSERT INTO user_settings (id, json, updated_at) VALUES (1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at;
        """, [.text(JSONCoding.encode(settings)), .date(Date())])
    }
}
