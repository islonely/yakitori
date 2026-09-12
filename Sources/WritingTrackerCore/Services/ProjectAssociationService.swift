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
    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("WritingTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("WritingTracker.sqlite")
    }

    public static var backupsDirectory: URL {
        let dir = applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var exportsDirectory: URL {
        let dir = applicationSupportDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
