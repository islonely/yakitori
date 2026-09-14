import Foundation

/// Composition root. Wires persistence, services, and the tracking engine
/// together. The UI depends only on this container (never directly on SQLite).
public final class AppContainer {
    public let database: Database
    public let permissionProvider: PermissionProviding
    public let dateProvider: DateProviding
    public let calendarContext: CalendarContext

    public let statistics: StatisticsService
    public let analytics: AnalyticsService
    public let projects: ProjectService
    public let goals: GoalService
    public let sessions: SessionService
    public let reports: ReportService
    public let export: ExportService
    public let backup: BackupService
    public let dataManagement: DataManagementService
    public let notifications: NotificationService
    public let association: ProjectAssociationService
    public let social: SocialService
    public let trackingEngine: TrackingEngine
    public let settingsRepository: SettingsRepository
    public let applicationRepository: WritingApplicationRepository

    public private(set) var settings: UserSettings

    public init(
        database: Database,
        permissionProvider: PermissionProviding = PermissionManager(),
        dateProvider: DateProviding = SystemDateProvider(),
        calendarContext: CalendarContext = CalendarContext(),
        registry: AdapterRegistry = .shared,
        idleProvider: SystemIdleProviding = CGSystemIdleProvider()
    ) {
        self.database = database
        self.permissionProvider = permissionProvider
        self.dateProvider = dateProvider
        self.calendarContext = calendarContext
        self.settingsRepository = SettingsRepository(database: database)
        self.applicationRepository = WritingApplicationRepository(database: database)
        self.settings = (try? settingsRepository.load()) ?? .default

        self.statistics = StatisticsService(database: database, dateProvider: dateProvider, calendarContext: calendarContext, settings: settings)
        self.analytics = AnalyticsService(database: database, statistics: statistics, dateProvider: dateProvider)
        self.projects = ProjectService(database: database)
        self.goals = GoalService(database: database, statistics: statistics)
        self.sessions = SessionService(database: database, statistics: statistics)
        self.reports = ReportService(statistics: statistics, dateProvider: dateProvider, calendarContext: calendarContext)
        self.export = ExportService(database: database, statistics: statistics, dateProvider: dateProvider)
        self.backup = BackupService(database: database, dateProvider: dateProvider)
        self.dataManagement = DataManagementService(database: database, backupService: backup, statistics: statistics)
        self.notifications = NotificationService(database: database)
        self.association = ProjectAssociationService(database: database)
        self.social = SocialService(database: database, statistics: statistics, dateProvider: dateProvider)
        self.trackingEngine = TrackingEngine(
            database: database,
            permissionProvider: permissionProvider,
            dateProvider: dateProvider,
            registry: registry,
            idleProvider: idleProvider,
            projectResolver: association,
            calendarContext: calendarContext
        )
    }

    // MARK: - Settings

    public func saveSettings(_ newSettings: UserSettings) {
        var value = newSettings
        value.schemaVersion = 1
        settings = value
        try? settingsRepository.save(value)
        statistics.refreshSettings()
        notifications.refreshSettings()
        association.reload()
        trackingEngine.reloadSettings()
    }

    public func reloadSettings() {
        settings = (try? settingsRepository.load()) ?? settings
        statistics.refreshSettings()
        notifications.refreshSettings()
        association.reload()
    }

    // MARK: - First launch bootstrap

    /// Seeds detected writing applications and a default daily goal for new users.
    /// Never overwrites existing user configuration.
    public func bootstrapIfNeeded() {
        if (try? applicationRepository.count()) == 0 {
            let detected = AdapterRegistry.shared.detectedApplications()
            var selected: [String] = []
            for app in detected {
                let record = WritingApplication(
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.displayName,
                    adapterType: app.adapterType,
                    category: .writing,
                    enabled: true,
                    automaticTrackingEnabled: true
                )
                try? applicationRepository.insert(record)
                selected.append(record.id)
            }
            if settings.selectedApplicationIDs.isEmpty, !selected.isEmpty {
                var updated = settings
                updated.selectedApplicationIDs = selected
                try? settingsRepository.save(updated)
                settings = updated
            }
        }
        statistics.refreshSettings()
        try? goals.ensureDefaultGoal()
    }
}
