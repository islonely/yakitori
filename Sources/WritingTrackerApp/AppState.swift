import AppKit
import Foundation
import SwiftUI
import WritingTrackerCore

/// High-frequency live tracking state, kept separate from `AppState` so that
/// live updates (which can occur once per second while typing) never invalidate
/// the data-heavy dashboard/statistics views.
@MainActor
final class TrackingModel: ObservableObject {
    @Published var snapshot: TrackingSnapshot = .idle
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let container: AppContainer
    let bootstrapError: Error?
    let tracking = TrackingModel()

    @Published var settings: UserSettings
    @Published var permissionStatuses: [PermissionStatus] = []
    @Published var selectedSection: SidebarSection = .dashboard
    @Published var selectedProjectID: String?
    /// Increments only when persisted history changes (sessions, projects, settings).
    @Published var dataVersion: Int = 0
    @Published var alertMessage: String?
    @Published var isOnboardingPresented = false

    @Published var accountState: AccountState = .signedOut
    @Published var licensingState: LicensingState = .signedOut
    @Published var deviceAuthorization: DeviceAuthorization?
    @Published var isDeviceSignInPresented = false
    @Published var deviceSignInError: String?

    private var isStarted = false
    private var devicePollingTask: Task<Void, Never>?
    private let globalHotkey = GlobalHotkey()

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

        // Live updates are cheap and only touch the tracking model.
        container.trackingEngine.onChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.tracking.snapshot = self.container.trackingEngine.snapshot()
            }
        }
        // Persisted-history updates invalidate data-driven views.
        container.trackingEngine.onDataChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        container.trackingEngine.onSessionEnded = { [weak self] in
            Task { @MainActor in self?.publishCommunityStats() }
        }
        container.permissionProvider.onChange = { [weak self] in
            Task { @MainActor in self?.refreshPermissions() }
        }

        // The engine always runs so manual sessions work even when automatic
        // tracking-at-launch is disabled.
        container.trackingEngine.start()

        refreshPermissions()
        refresh()
        tracking.snapshot = container.trackingEngine.snapshot()

        if !settings.onboardingCompleted {
            isOnboardingPresented = true
        }
        container.notifications.requestAuthorizationIfNeeded()
        configureGlobalHotkey()
        configureAccount()

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
        devicePollingTask?.cancel()
        container.trackingEngine.endActiveSession()
        container.trackingEngine.stop()
    }

    // MARK: - Account and licensing

    private func configureAccount() {
        container.account.onStateChange = { [weak self] state in
            Task { @MainActor in self?.handleAccountState(state) }
        }
        container.licensing.onStateChange = { [weak self] state in
            Task { @MainActor in self?.licensingState = state }
        }
        accountState = container.account.state

        // Restore a stored session in the background; tracking is unaffected.
        Task { await restoreAccountIfPossible() }
    }

    private func restoreAccountIfPossible() async {
        let restored = await container.account.restoreSession()
        accountState = container.account.state
        if restored {
            await container.licensing.refresh()
        } else {
            licensingState = .signedOut
        }
    }

    private func handleAccountState(_ state: AccountState) {
        accountState = state
        switch state {
        case .signedIn:
            Task { await container.licensing.refresh() }
        case .signedOut:
            Task { await container.licensing.setSignedIn(false) }
        case .error:
            break
        }
    }

    func beginDeviceSignIn() {
        deviceSignInError = nil
        Task {
            do {
                let authorization = try await container.account.beginSignIn()
                deviceAuthorization = authorization
                isDeviceSignInPresented = true
                let urlString = authorization.verificationUriComplete ?? authorization.verificationUri
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
                startPollingDeviceAuthorization(authorization)
            } catch {
                deviceSignInError = error.localizedDescription
            }
        }
    }

    private func startPollingDeviceAuthorization(_ authorization: DeviceAuthorization) {
        devicePollingTask?.cancel()
        devicePollingTask = Task { [weak self] in
            guard let self else { return }
            let interval = max(1, authorization.interval)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }

                do {
                    let result = try await self.container.account.pollForToken(authorization)
                    switch result {
                    case .pending, .slowDown:
                        continue
                    case .authorized(let token):
                        try await self.container.account.completeSignIn(token: token.token)
                        self.isDeviceSignInPresented = false
                        self.deviceAuthorization = nil
                        self.accountState = self.container.account.state
                        await self.container.licensing.refresh()
                        return
                    }
                } catch {
                    self.deviceSignInError = error.localizedDescription
                    self.isDeviceSignInPresented = false
                    return
                }
            }
        }
    }

    func cancelDeviceSignIn() {
        devicePollingTask?.cancel()
        isDeviceSignInPresented = false
        deviceAuthorization = nil
    }

    func openDeviceVerificationPage() {
        guard let authorization = deviceAuthorization else { return }
        let string = authorization.verificationUriComplete ?? authorization.verificationUri
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    func signOutAccount() {
        devicePollingTask?.cancel()
        Task {
            await container.account.signOut()
            await container.licensing.setSignedIn(false)
            accountState = .signedOut
            licensingState = .signedOut
        }
    }

    func refreshLicense() {
        Task { await container.licensing.refresh() }
    }

    /// Reloads persisted data and settings. Called after any structural change.
    func refresh() {
        settings = container.settings
        dataVersion &+= 1
        tracking.snapshot = container.trackingEngine.snapshot()
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

    func openPrivacySettings() {
        container.permissionProvider.openPrivacySettings()
    }

    // MARK: - Settings

    func save(_ newSettings: UserSettings) {
        container.saveSettings(newSettings)
        settings = container.settings
        refreshPermissions()
        configureGlobalHotkey()
        publishCommunityStats()
        refresh()
    }

    // MARK: - Community

    /// Publishes the writer's aggregate stats when they have opted in.
    func publishCommunityStats() {
        guard settings.publishStatsEnabled else { return }
        let trimmed = settings.communityDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty == false ? trimmed! : "You")
        try? container.social.publishSelf(displayName: name)
    }

    func unpublishCommunityStats() {
        try? container.social.removeSelf()
    }

    // MARK: - Global hotkey

    private func configureGlobalHotkey() {
        globalHotkey.unregister()
        globalHotkey.onTrigger = nil
        guard let config = settings.globalHotkey, config.enabled else { return }
        globalHotkey.onTrigger = { [weak self] in
            Task { @MainActor in self?.toggleSessionFromHotkey() }
        }
        _ = globalHotkey.register(keyCode: config.keyCode, carbonModifiers: config.carbonModifiers)
    }

    private func toggleSessionFromHotkey() {
        if tracking.snapshot.isSessionOpen {
            stopSession()
        } else {
            startManualSession(projectID: settings.currentProjectID, type: settings.defaultSessionType)
        }
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
        let id = tracking.snapshot.currentProjectID ?? settings.currentProjectID
        guard let id else { return nil }
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
    case community
    case account
    case settings
    case privacy

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
        case .community: return "Community"
        case .account: return "Account"
        case .settings: return "Settings"
        case .privacy: return "Privacy"
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
        case .community: return "person.3"
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        case .privacy: return "hand.raised"
        }
    }
}
