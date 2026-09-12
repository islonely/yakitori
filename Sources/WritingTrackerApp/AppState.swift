import Foundation
import SwiftUI
import WritingTrackerCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let container: AppContainer
    let bootstrapError: Error?

    @Published var tracking: TrackingSnapshot = .idle
    @Published var settings: UserSettings
    @Published var permissionStatuses: [PermissionStatus] = []
    @Published var selectedSection: SidebarSection = .dashboard
    @Published var selectedProjectID: String?
    @Published var dataVersion: Int = 0
    @Published var alertMessage: String?
    @Published var isOnboardingPresented = false

    private var isStarted = false

    private init() {
        let (db, didFail) = Self.makeDatabase()
        self.container = AppContainer(database: db)
        self.bootstrapError = didFail
        self.settings = container.settings
    }

    private static func makeDatabase() -> (SQLiteDatabase, Error?) {
        do {
            let db = try SQLiteDatabase(path: AppPaths.databaseURL.path)
            try Migrator(database: db).migrate()
            return (db, nil)
        } catch {
            // Fall back to an in-memory database so the app still launches, but
            // surface the problem rather than pretending data is saved.
            let memory = try! SQLiteDatabase.inMemory()
            _ = try? Migrator(database: memory).migrate()
            return (memory, error)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        container.bootstrapIfNeeded()
        settings = container.settings
        if bootstrapError != nil {
            alertMessage = "The database could not be opened. Running with temporary storage; data will not persist. \(bootstrapError?.localizedDescription ?? "")"
        }
        container.trackingEngine.onChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        container.permissionProvider.onChange = { [weak self] in
            Task { @MainActor in self?.refreshPermissions() }
        }
        // The engine always runs so manual sessions work even when automatic
        // tracking-at-launch is disabled.
        container.trackingEngine.start()
        refreshPermissions()
        refresh()
        if !settings.onboardingCompleted {
            isOnboardingPresented = true
        }
        container.notifications.requestAuthorizationIfNeeded()

        // Re-check permissions when the user returns from System Settings.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.container.permissionProvider.refresh()
                self?.refreshPermissions()
            }
        }
    }

    func shutdown() {
        container.trackingEngine.endActiveSession()
        container.trackingEngine.stop()
    }

    func refresh() {
        tracking = container.trackingEngine.snapshot()
        settings = container.settings
        dataVersion &+= 1
    }

    func refreshPermissions() {
        permissionStatuses = PermissionKind.allCases.map { container.permissionProvider.status(for: $0) }
    }

    func permissionStatus(for kind: PermissionKind) -> PermissionState {
        container.permissionProvider.status(for: kind).state
    }

    func requestPermission(_ kind: PermissionKind) {
        container.permissionProvider.request(kind)
        refreshPermissions()
    }

    func openSystemSettings(for kind: PermissionKind) {
        container.permissionProvider.openSystemSettings(for: kind)
    }

    // MARK: - Settings

    func save(_ newSettings: UserSettings) {
        container.saveSettings(newSettings)
        settings = container.settings
        refreshPermissions()
        refresh()
    }

    func updateSettings(_ mutate: (inout UserSettings) -> Void) {
        var value = settings
        mutate(&value)
        save(value)
    }

    // MARK: - Tracking controls

    func startManualSession(projectID: String?, type: SessionType) {
        container.trackingEngine.startManualSession(projectID: projectID, type: type)
        refresh()
    }

    func pauseSession() {
        container.trackingEngine.pauseSession()
        refresh()
    }

    func resumeSession() {
        container.trackingEngine.resumeSession()
        refresh()
    }

    func stopSession() {
        container.trackingEngine.stopSession()
        container.notifications.evaluateGoals(statistics: container.statistics)
        refresh()
    }

    func setCurrentProject(_ projectID: String?) {
        container.trackingEngine.setCurrentProject(projectID)
        updateSettings { $0.currentProjectID = projectID }
    }

    // MARK: - Convenience

    var currentProject: Project? {
        guard let id = tracking.currentProjectID ?? settings.currentProjectID else { return nil }
        return try? container.projects.project(id: id)
    }

    func presentError(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    func completeOnboarding() {
        updateSettings { $0.onboardingCompleted = true }
        container.notifications.requestAuthorizationIfNeeded()
        isOnboardingPresented = false
    }
}

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case statistics
    case calendar
    case sessions
    case projects
    case goals
    case reports
    case achievements
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .statistics: return "Statistics"
        case .calendar: return "Calendar"
        case .sessions: return "Sessions"
        case .projects: return "Projects"
        case .goals: return "Goals"
        case .reports: return "Reports"
        case .achievements: return "Achievements"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .statistics: return "chart.bar.xaxis"
        case .calendar: return "calendar"
        case .sessions: return "list.bullet.rectangle"
        case .projects: return "books.vertical"
        case .goals: return "target"
        case .reports: return "doc.text"
        case .achievements: return "trophy"
        case .settings: return "gearshape"
        }
    }
}
