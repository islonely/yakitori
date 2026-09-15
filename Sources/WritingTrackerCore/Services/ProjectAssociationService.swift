import Foundation

/// Pure project-association policy, kept separate from the tracking engine so it
/// can be unit tested.
///
/// Priority: an explicit manual choice wins; otherwise the document's own
/// association; otherwise the resolver's rule-based match; otherwise the
/// user's current project.
public enum ProjectResolution {
    public static func effectiveProjectID(
        documentProjectID: String?,
        resolvedProjectID: String?,
        currentProjectID: String?,
        isManual: Bool,
        manualProjectID: String?
    ) -> String? {
        if isManual, let manualProjectID { return manualProjectID }
        return documentProjectID ?? resolvedProjectID ?? currentProjectID
    }
}

/// Resolves activity to a project using the documented association priority:
/// explicit user association > exact document > folder rule > project-file
/// recognition > application-specific project > manual assignment.
public final class ProjectAssociationService: ProjectResolving {    private let ruleRepository: AssociationRuleRepository
    private let documentRepository: DocumentRepository
    private let settingsRepository: SettingsRepository
    private var rules: [AssociationRule] = []
    private var settings: UserSettings
    private let lock = NSLock()

    public init(database: Database) {
        self.ruleRepository = AssociationRuleRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
        self.settingsRepository = SettingsRepository(database: database)
        self.settings = (try? settingsRepository.load()) ?? .default
        reload()
    }

    public func reload() {
        lock.lock(); defer { lock.unlock() }
        rules = (try? ruleRepository.all()) ?? []
        settings = (try? settingsRepository.load()) ?? settings
    }

    public func resolveProjectID(documentPath: String?, documentName: String?, applicationID: String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard settings.automaticProjectMatching else { return nil }

        // Exact document association.
        if let path = documentPath, let document = try? documentRepository.find(filePath: path), let projectID = document.projectID {
            return projectID
        }
        if let path = documentPath, let document = try? documentRepository.find(stableIdentifier: path), let projectID = document.projectID {
            return projectID
        }

        // Folder rule (longest matching prefix wins).
        if let path = documentPath {
            let folderRules = rules
                .filter { $0.type == .folderPath && path.hasPrefix($0.value) }
                .sorted { $0.value.count > $1.value.count }
            if let match = folderRules.first { return match.projectID }
        }

        // Exact file rule.
        if let path = documentPath, let rule = rules.first(where: { $0.type == .filePath && $0.value == path }) {
            return rule.projectID
        }

        // Document name rule.
        if let name = documentName, let rule = rules.first(where: { $0.type == .documentName && $0.value == name }) {
            return rule.projectID
        }

        // Application-specific project recognition.
        if let applicationID, let rule = rules.first(where: { $0.type == .applicationProject && $0.value == applicationID }) {
            return rule.projectID
        }

        return nil
    }
}

public enum AppPaths {
    static let folderName = "Yakitori"
    static let databaseFileName = "Yakitori.sqlite"

    /// Resolved once per process. Prefers iCloud Drive so the data syncs
    /// between Macs, falling back to Application Support.
    static let resolvedDataDirectory: URL = resolveDataDirectory(
        environment: ProcessInfo.processInfo.environment,
        fileManager: .default,
        iCloudContainer: shouldUseICloud(
            environment: ProcessInfo.processInfo.environment,
            fileManager: .default
        ) ? iCloudDriveContainer(fileManager: .default) : nil,
        localSupport: localApplicationSupport(fileManager: .default)
    )

    /// Where Yakitori keeps its database, backups, exports, and community file.
    public static var dataDirectory: URL { resolvedDataDirectory }

    /// True when the data lives in iCloud Drive (and is therefore syncing).
    public static var isICloudBacked: Bool { isCloudPath(resolvedDataDirectory) }

    /// The database file.
    public static var databaseURL: URL {
        resolvedDataDirectory.appendingPathComponent(databaseFileName)
    }

    public static var backupsDirectory: URL {
        ensureDirectory(resolvedDataDirectory.appendingPathComponent("Backups", isDirectory: true))
    }

    public static var exportsDirectory: URL {
        ensureDirectory(resolvedDataDirectory.appendingPathComponent("Exports", isDirectory: true))
    }

    /// Placeholder community/leaderboard store until an online service exists.
    public static var communityDataURL: URL {
        resolvedDataDirectory.appendingPathComponent("community.json")
    }

    // MARK: - Resolution

    static func resolveDataDirectory(
        environment: [String: String],
        fileManager: FileManager,
        iCloudContainer: URL?,
        localSupport: URL
    ) -> URL {
        // 1. Explicit override (tests, power users, or a chosen sync folder).
        if let override = environment["YAKITORI_DATA_DIR"], !override.isEmpty {
            return ensureDirectory(URL(fileURLWithPath: override, isDirectory: true))
        }

        // 2. iCloud Drive, so data syncs between Macs.
        if let iCloudContainer {
            let directory = ensureDirectory(
                iCloudContainer.appendingPathComponent(folderName, isDirectory: true)
            )
            migrateLocalStoreIfNeeded(
                destination: directory,
                localSupport: localSupport,
                fileManager: fileManager
            )
            return directory
        }

        // 3. Local Application Support.
        return ensureDirectory(
            localSupport.appendingPathComponent(folderName, isDirectory: true)
        )
    }

    static func shouldUseICloud(environment: [String: String], fileManager: FileManager) -> Bool {
        if let raw = environment["YAKITORI_USE_ICLOUD"] {
            return !["0", "false", "no", "off"].contains(raw.lowercased())
        }
        if let value = Bundle.main.object(
            forInfoDictionaryKey: "YakitoriUseICloudDrive"
        ) as? Bool {
            return value
        }
        return true
    }

    static func iCloudDriveContainer(fileManager: FileManager) -> URL? {
        let container = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: container.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return container
    }

    static func localApplicationSupport(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    static func isCloudPath(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("com~apple~CloudDocs") || path.contains("Mobile Documents")
    }

    @discardableResult
    static func ensureDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies an existing local database into iCloud the first time it is used.
    ///
    /// The local copy is deliberately left in place: this is a non-destructive
    /// move, so nothing is lost if iCloud Drive is later disabled.
    private static func migrateLocalStoreIfNeeded(
        destination: URL,
        localSupport: URL,
        fileManager: FileManager
    ) {
        let localDirectory = localSupport.appendingPathComponent(folderName, isDirectory: true)
        let localDatabase = localDirectory.appendingPathComponent(databaseFileName)
        let destinationDatabase = destination.appendingPathComponent(databaseFileName)

        guard !fileManager.fileExists(atPath: destinationDatabase.path),
              fileManager.fileExists(atPath: localDatabase.path)
        else {
            return
        }

        var migrated = false
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: localDatabase.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: destinationDatabase.path + suffix)
            try? fileManager.removeItem(at: target)
            if (try? fileManager.copyItem(at: source, to: target)) != nil {
                migrated = true
            }
        }

        let localCommunity = localDirectory.appendingPathComponent("community.json")
        if fileManager.fileExists(atPath: localCommunity.path) {
            let target = destination.appendingPathComponent("community.json")
            if !fileManager.fileExists(atPath: target.path) {
                try? fileManager.copyItem(at: localCommunity, to: target)
            }
        }

        if migrated {
            Log.app.notice("Migrated Yakitori data to iCloud Drive (local copy kept)")
        }
    }
}
