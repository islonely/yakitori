import Foundation

/// A single versioned, forward-only schema migration.
public struct Migration {
    public let version: Int
    public let name: String
    public let up: (Database) throws -> Void

    public init(version: Int, name: String, up: @escaping (Database) throws -> Void) {
        self.version = version
        self.name = name
        self.up = up
    }
}

/// Applies versioned migrations using `PRAGMA user_version`.
///
/// Migrations are additive and never drop user data. If a migration fails the
/// transaction is rolled back and the previous version is preserved.
public final class Migrator {
    private let database: Database
    private let migrations: [Migration]

    public init(database: Database, migrations: [Migration] = Migrations.all) {
        self.database = database
        self.migrations = migrations.sorted { $0.version < $1.version }
    }

    public var currentVersion: Int {
        (try? database.scalar("PRAGMA user_version;")?.intValue) ?? 0
    }

    @discardableResult
    public func migrate() throws -> Int {
        var version = currentVersion
        for migration in migrations where migration.version > version {
            Log.database.info("Applying migration \(migration.version, privacy: .public): \(migration.name, privacy: .public)")
            do {
                try database.transaction {
                    try migration.up(database)
                }
                try database.execute("PRAGMA user_version = \(migration.version);")
                version = migration.version
            } catch {
                throw WritingTrackerError.migrationFailed(
                    "v\(migration.version) \(migration.name): \(error.localizedDescription)"
                )
            }
        }
        return version
    }
}

public enum Migrations {
    public static let all: [Migration] = [
        Migration(version: 1, name: "initial_schema") { db in
            try db.execute("""
            CREATE TABLE IF NOT EXISTS writing_applications (
                id TEXT PRIMARY KEY,
                bundle_identifier TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                icon_reference TEXT,
                adapter_type TEXT NOT NULL,
                category TEXT NOT NULL DEFAULT 'writing',
                enabled INTEGER NOT NULL DEFAULT 1,
                automatic_tracking_enabled INTEGER NOT NULL DEFAULT 1,
                configuration TEXT NOT NULL DEFAULT '{}',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """)

            try db.execute("""
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                type TEXT NOT NULL,
                description TEXT,
                status TEXT NOT NULL,
                target_word_count INTEGER,
                starting_word_count INTEGER NOT NULL DEFAULT 0,
                current_word_count INTEGER NOT NULL DEFAULT 0,
                deadline REAL,
                created_at REAL NOT NULL,
                started_at REAL,
                completed_at REAL,
                archived_at REAL
            );
            """)

            try db.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                project_id TEXT,
                application_id TEXT,
                display_name TEXT NOT NULL,
                stable_identifier TEXT,
                file_path TEXT,
                created_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL,
                FOREIGN KEY(application_id) REFERENCES writing_applications(id) ON DELETE SET NULL
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_documents_path ON documents(file_path);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_documents_stable ON documents(stable_identifier);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_documents_project ON documents(project_id);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                project_id TEXT,
                document_id TEXT,
                application_id TEXT,
                started_at REAL NOT NULL,
                ended_at REAL,
                active_seconds REAL NOT NULL DEFAULT 0,
                focus_seconds REAL NOT NULL DEFAULT 0,
                starting_word_count INTEGER,
                ending_word_count INTEGER,
                words_added INTEGER,
                words_removed INTEGER,
                net_word_change INTEGER,
                session_type TEXT NOT NULL DEFAULT 'unknown',
                notes TEXT,
                active_ranges TEXT NOT NULL DEFAULT '[]',
                focus_ranges TEXT NOT NULL DEFAULT '[]',
                is_recovered INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE SET NULL,
                FOREIGN KEY(application_id) REFERENCES writing_applications(id) ON DELETE SET NULL
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_sessions_app ON sessions(application_id);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_sessions_open ON sessions(ended_at);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                application_id TEXT,
                event_type TEXT NOT NULL,
                session_id TEXT,
                metadata TEXT NOT NULL DEFAULT '{}'
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_events_timestamp ON activity_events(timestamp);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_events_session ON activity_events(session_id);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS word_count_snapshots (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                document_id TEXT,
                project_id TEXT,
                word_count INTEGER NOT NULL,
                character_count INTEGER,
                page_count INTEGER,
                source TEXT NOT NULL DEFAULT 'unknown'
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON word_count_snapshots(timestamp);")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_snapshots_document ON word_count_snapshots(document_id);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS daily_aggregates (
                day_key TEXT PRIMARY KEY,
                date REAL NOT NULL,
                words_added INTEGER NOT NULL DEFAULT 0,
                words_removed INTEGER NOT NULL DEFAULT 0,
                net_words INTEGER NOT NULL DEFAULT 0,
                active_seconds REAL NOT NULL DEFAULT 0,
                focus_seconds REAL NOT NULL DEFAULT 0,
                session_count INTEGER NOT NULL DEFAULT 0,
                project_count INTEGER NOT NULL DEFAULT 0,
                first_session_at REAL,
                last_session_at REAL
            );
            """)

            try db.execute("""
            CREATE TABLE IF NOT EXISTS goals (
                id TEXT PRIMARY KEY,
                project_id TEXT,
                period TEXT NOT NULL,
                metric TEXT NOT NULL,
                target REAL NOT NULL,
                start_date REAL NOT NULL,
                end_date REAL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            """)

            try db.execute("""
            CREATE TABLE IF NOT EXISTS milestones (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                title TEXT NOT NULL,
                target_value REAL,
                metric TEXT,
                completed_at REAL,
                created_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_milestones_project ON milestones(project_id);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS writing_schedules (
                id TEXT PRIMARY KEY,
                weekday INTEGER NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                target_minutes INTEGER,
                target_words INTEGER
            );
            """)

            try db.execute("""
            CREATE TABLE IF NOT EXISTS association_rules (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                type TEXT NOT NULL,
                value TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );
            """)
            try db.execute("CREATE INDEX IF NOT EXISTS idx_rules_project ON association_rules(project_id);")

            try db.execute("""
            CREATE TABLE IF NOT EXISTS user_settings (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """)
        },

        // Reserved column (kept so schema versions stay consistent). Records the
        // provenance of a session's word counts for future use.
        Migration(version: 2, name: "reserved_word_count_source") { db in
            try db.execute("ALTER TABLE sessions ADD COLUMN word_count_source TEXT NOT NULL DEFAULT 'none';")
        }
    ]
}
