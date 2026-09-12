import Foundation

/// Local database backup. A safe backup is created before any destructive data
/// operation, per the repository's data-safety rules.
public final class BackupService {
    private let database: Database
    private let databaseURL: URL?
    private let backupsDirectory: URL
    private let dateProvider: DateProviding
    private let fileManager = FileManager.default

    public init(
        database: Database,
        databaseURL: URL? = AppPaths.databaseURL,
        backupsDirectory: URL = AppPaths.backupsDirectory,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.database = database
        self.databaseURL = databaseURL
        self.backupsDirectory = backupsDirectory
        self.dateProvider = dateProvider
    }

    public struct Backup: Identifiable, Hashable {
        public var id: String { url.path }
        public let url: URL
        public let createdAt: Date
        public let byteSize: Int
    }

    @discardableResult
    public func createBackup(label: String = "manual") throws -> URL {
        guard let databaseURL, fileManager.fileExists(atPath: databaseURL.path) else {
            throw WritingTrackerError.databaseUnavailable("No on-disk database to back up")
        }
        // Flush the WAL so the main file is self-contained.
        _ = try? database.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone.current
        let stamp = formatter.string(from: dateProvider.now)
        let destination = backupsDirectory.appendingPathComponent("WritingTracker-\(stamp)-\(label).sqlite")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: databaseURL, to: destination)

        // Verify the backup is a readable SQLite file.
        guard fileManager.fileExists(atPath: destination.path),
              let size = try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int,
              size > 0 else {
            throw WritingTrackerError.databaseUnavailable("Backup verification failed")
        }
        Log.database.info("Created database backup at \(destination.lastPathComponent, privacy: .public)")
        return destination
    }

    public func listBackups() -> [Backup] {
        guard let urls = try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "sqlite" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return Backup(
                    url: url,
                    createdAt: values?.creationDate ?? Date.distantPast,
                    byteSize: values?.fileSize ?? 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func pruneBackups(keeping keep: Int) {
        let backups = listBackups()
        guard backups.count > keep else { return }
        for backup in backups.dropFirst(keep) {
            try? fileManager.removeItem(at: backup.url)
        }
    }

    public func deleteBackup(_ backup: Backup) throws {
        try fileManager.removeItem(at: backup.url)
    }
}

/// Destructive data operations. Each one creates a verified backup first.
public final class DataManagementService {
    private let database: Database
    private let backupService: BackupService
    private let statistics: StatisticsService

    public init(database: Database, backupService: BackupService, statistics: StatisticsService) {
        self.database = database
        self.backupService = backupService
        self.statistics = statistics
    }

    /// Deletes all session history but keeps projects and settings.
    @discardableResult
    public func deleteSessionHistory() throws -> URL {
        let backup = try backupService.createBackup(label: "before-session-delete")
        try database.transaction {
            try database.execute("DELETE FROM activity_events;")
            try database.execute("DELETE FROM word_count_snapshots;")
            try database.execute("DELETE FROM sessions;")
            try database.execute("DELETE FROM daily_aggregates;")
        }
        return backup
    }

    /// Deletes all statistics (sessions, events, snapshots, aggregates).
    @discardableResult
    public func deleteAllStatistics() throws -> URL {
        try deleteSessionHistory()
    }

    /// Deletes a project and all of its associated data.
    public func deleteProject(projectID: String) throws {
        _ = try backupService.createBackup(label: "before-project-delete")
        try database.transaction {
            try database.execute("DELETE FROM sessions WHERE project_id = ?;", [.text(projectID)])
            try database.execute("DELETE FROM documents WHERE project_id = ?;", [.text(projectID)])
            try database.execute("DELETE FROM projects WHERE id = ?;", [.text(projectID)])
        }
        statistics.rebuildDailyAggregates()
    }

    /// Full factory reset. Creates a backup first so nothing is irrecoverable.
    @discardableResult
    public func factoryReset() throws -> URL {
        let backup = try backupService.createBackup(label: "before-factory-reset")
        try database.transaction {
            try database.execute("DELETE FROM activity_events;")
            try database.execute("DELETE FROM word_count_snapshots;")
            try database.execute("DELETE FROM sessions;")
            try database.execute("DELETE FROM daily_aggregates;")
            try database.execute("DELETE FROM documents;")
            try database.execute("DELETE FROM goals;")
            try database.execute("DELETE FROM milestones;")
            try database.execute("DELETE FROM association_rules;")
            try database.execute("DELETE FROM projects;")
            try database.execute("DELETE FROM writing_applications;")
            try database.execute("DELETE FROM user_settings;")
        }
        return backup
    }

    public func rebuildAggregates() -> Int {
        statistics.rebuildDailyAggregates()
    }
}
