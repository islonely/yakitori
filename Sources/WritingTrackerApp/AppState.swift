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

    /// Swapped when the signed-in account changes so each account has its own
    /// database, backups, and community file.
    private(set) var container: AppContainer
    private var bootstrapError: Error?
    let tracking = TrackingModel()

    // Stable across account switches.
    let accountService: AccountService
    let licensingService: LicensingService
    let permissionProvider: PermissionProviding
    let dateProvider: DateProviding
    let calendarContext: CalendarContext

    @Published var settings: UserSettings
    @Published var permissionStatuses: [PermissionStatus] = []
    @Published var selectedSection: SidebarSection = .dashboard
    @Published var selectedProjectID: String?
    /// Increments only when persisted history changes (sessions, projects, settings).
    @Published var dataVersion: Int = 0
    @Published var alertMessage: String?
    @Published var isOnboardingPresented = false

    @Published var accountState: AccountState = .signedOut
    /// True once the stored session has been checked, so the UI can avoid a
    /// flash of the signed-out gate on launch.
    @Published var accountLoaded = false
    @Published var licensingState: LicensingState = .signedOut
    @Published var deviceAuthorization: DeviceAuthorization?
    @Published var isDeviceSignInPresented = false
    @Published var deviceSignInError: String?

    private var isStarted = false
    private var devicePollingTask: Task<Void, Never>?
    private var licenseTimerTask: Task<Void, Never>?
    private var lastLicenseRefresh = Date.distantPast
    private let globalHotkey = GlobalHotkey()
    /// The account whose data is currently loaded (nil = signed out).
    private var dataAccountKey: String?
    private var hasActivatedDataScope = false

    private init() {
        let configuration = PlatformConfiguration.fromBundle()
        let secretStore = KeychainSecretStore()
        self.accountService = AccountService(
            configuration: configuration,
            transport: URLSessionTransport(),
            secrets: secretStore
        )
        self.licensingService = LicensingService(
            configuration: configuration,
            transport: URLSessionTransport(),
            secrets: secretStore,
            dateProvider: SystemDateProvider()
        )
        let permissions = PermissionManager()
        self.permissionProvider = permissions
        self.dateProvider = SystemDateProvider()
        self.calendarContext = CalendarContext()

        // Placeholder until the account (and therefore the data scope) is known.
        // No real data is read or shown before `accountLoaded`.
        let placeholder = try! SQLiteDatabase.inMemory()
        _ = try? Migrator(database: placeholder).migrate()
        self.container = AppContainer(
            database: placeholder,
            permissionProvider: permissions
        )
        self.settings = container.settings
    }

    /// Opens the data container for an account. `nil` means signed out, which
    /// keeps data out of any persistent store.
    private static func makeContainer(
        accountKey: String?,
        permissionProvider: PermissionProviding
    ) -> (AppContainer, Error?) {
        guard let accountKey else {
            let memory = try! SQLiteDatabase.inMemory()
            _ = try? Migrator(database: memory).migrate()
            return (
                AppContainer(database: memory, permissionProvider: permissionProvider),
                nil
            )
        }

        do {
            let url = AppPaths.databaseURL(forAccountKey: accountKey)
            let database = try SQLiteDatabase(path: url.path)
            try Migrator(database: database).migrate()
            return (
                AppContainer(
                    database: database,
                    dataDirectory: AppPaths.accountDataDirectory(for: accountKey),
                    permissionProvider: permissionProvider
                ),
                nil
            )
        } catch {
            // Fall back to in-memory so the app still launches, but surface the
            // problem rather than pretending data is saved.
            let memory = try! SQLiteDatabase.inMemory()
            _ = try? Migrator(database: memory).migrate()
            return (
                AppContainer(database: memory, permissionProvider: permissionProvider),
                error
            )
        }
    }

    /// Loads the given account's data, rebuilding the container and engine.
    /// Runs on first account resolution and whenever the account changes.
    private func activateDataScope(for accountKey: String?) {
        if hasActivatedDataScope && accountKey == dataAccountKey { return }

        container.trackingEngine.endActiveSession()
        container.trackingEngine.stop()

        let (newContainer, error) = Self.makeContainer(
            accountKey: accountKey,
            permissionProvider: permissionProvider
        )
        container = newContainer
        dataAccountKey = accountKey
        hasActivatedDataScope = true
        bootstrapError = error

        wireContainerCallbacks()
        newContainer.bootstrapIfNeeded()
        newContainer.trackingEngine.setTrackingAllowed(licensingState.isUsable)
        newContainer.trackingEngine.start()

        settings = newContainer.settings
        if isSignedIn && !settings.onboardingCompleted {
            isOnboardingPresented = true
        }
        newContainer.notifications.requestAuthorizationIfNeeded()
        configureGlobalHotkey()
        refreshPermissions()
        refresh()
        tracking.snapshot = newContainer.trackingEngine.snapshot()

        if let error {
            alertMessage = "This account's database could not be opened. Running with temporary storage; data will not persist. \(error.localizedDescription)"
        }
    }

    private func wireContainerCallbacks() {
        let engine = container.trackingEngine
        // Live updates are cheap and only touch the tracking model.
        engine.onChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.tracking.snapshot = self.container.trackingEngine.snapshot()
            }
        }
        // Persisted-history updates invalidate data-driven views.
        engine.onDataChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        engine.onSessionEnded = { [weak self] in
            Task { @MainActor in self?.publishCommunityStats() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        permissionProvider.onChange = { [weak self] in
            Task { @MainActor in self?.refreshPermissions() }
        }
        configureGlobalHotkey()
        configureAccount()

        // Re-check permissions when the user returns from System Settings.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.permissionProvider.refresh()
                self?.refreshPermissions()
                self?.refreshLicenseIfStale()
            }
        }

        // A trial can end while the Mac is asleep; the scheduled timer does not
        // fire during sleep, so re-check on wake as well.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLicenseIfStale() }
        }
    }

    func shutdown() {
        devicePollingTask?.cancel()
        licenseTimerTask?.cancel()
        container.trackingEngine.endActiveSession()
        container.trackingEngine.stop()
    }

    // MARK: - Account and licensing

    private func configureAccount() {
        accountService.onStateChange = { [weak self] state in
            Task { @MainActor in self?.handleAccountState(state) }
        }
        licensingService.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.licensingState = state
                self?.applyEntitlement(state)
                self?.scheduleEntitlementEvaluation()
            }
        }
        accountState = accountService.state
        // Until a license or trial is confirmed, recording stays off. The
        // engine keeps running so existing data stays viewable.
        applyEntitlement(licensingService.state)

        // Restore a stored session and validate the license in the background.
        Task { await restoreAccountIfPossible() }
    }

    /// Recording is the only thing gated by the entitlement. Everything the user
    /// has already written remains viewable and exportable.
    private func applyEntitlement(_ state: LicensingState) {
        // A transient ".checking" happens on every revalidation; it must not
        // tear down an active session. The previous gate stands until we have a
        // definitive answer.
        if state.isChecking { return }
        container.trackingEngine.setTrackingAllowed(state.isUsable)
    }

    /// Refreshes the entitlement when it is next due — critically, at the exact
    /// moment a trial ends, so a running session is stopped even if the app
    /// never contacts the server again.
    private func scheduleEntitlementEvaluation() {
        licenseTimerTask?.cancel()
        licenseTimerTask = nil

        guard licensingState.isUsable else { return }

        let now = Date()
        let delay: TimeInterval
        if let next = licensingService.nextEvaluationDate(now: now) {
            delay = max(30, next.timeIntervalSince(now) + 0.5)
        } else {
            // Offline grace with no fixed end: retry periodically.
            delay = 30 * 60
        }

        licenseTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.licensingService.refresh()
        }
    }

    /// Re-check when the app becomes active or the Mac wakes from sleep, in
    /// case the scheduled evaluation was missed while suspended.
    private func refreshLicenseIfStale() {
        let now = Date()
        guard now.timeIntervalSince(lastLicenseRefresh) > 60 else { return }
        guard isSignedIn else { return }
        lastLicenseRefresh = now
        Task { await licensingService.refresh() }
    }

    /// True when the signed-in user has no active license or trial, so the
    /// read-only banner should show.
    var entitlementBannerVisible: Bool {
        isSignedIn && !licensingState.isUsable && !licensingState.isChecking
    }

    /// Recording is allowed while entitled, and not torn down during a
    /// transient revalidation.
    var canRecordNewSessions: Bool {
        licensingState.isUsable || licensingState.isChecking
    }

    var entitlementMessage: String {
        switch licensingState {
        case .signedOut:
            return "Sign in to start your 14-day free trial. Yakitori needs an account so a trial can't be restarted."
        case .invalid(let reason) where reason == "trial_expired":
            return "Your 14-day free trial has ended. Buy a lifetime license to keep tracking new sessions."
        case .invalid(let reason) where reason == "trial_unavailable":
            return "This Mac has already used its free trial. Buy a lifetime license to keep tracking."
        case .invalid:
            return "Your license is not active. Open Account to review it."
        case .unavailable:
            return "Connect to the internet once to validate your license or start the free trial."
        case .clockAnomaly:
            return "The system clock looks wrong. Connect to the network to revalidate."
        case .checking:
            return "Checking your license…"
        default:
            return ""
        }
    }

    private func restoreAccountIfPossible() async {
        let restored = await accountService.restoreSession()
        accountState = accountService.state
        accountLoaded = true

        switch accountService.state {
        case .signedIn(let user):
            activateDataScope(for: user.id)
            await licensingService.refresh()
        case .signedOut:
            activateDataScope(for: nil)
            licensingState = .signedOut
        case .error:
            activateDataScope(for: nil)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = accountState { return true }
        return false
    }

    private func handleAccountState(_ state: AccountState) {
        accountState = state
        accountLoaded = true
        switch state {
        case .signedIn(let user):
            // Loading a different account's data is the whole point here.
            activateDataScope(for: user.id)
            Task { await licensingService.refresh() }
        case .signedOut:
            activateDataScope(for: nil)
            Task { await licensingService.setSignedIn(false) }
        case .error:
            break
        }
    }

    func beginDeviceSignIn() {
        deviceSignInError = nil
        Task {
            do {
                let authorization = try await accountService.beginSignIn()
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
            var interval = max(1, authorization.interval)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }

                do {
                    let result = try await self.accountService.pollForToken(authorization)
                    switch result {
                    case .pending:
                        continue
                    case .slowDown:
                        // Back off when the server asks us to (rate limit).
                        interval = min(interval + 5, 30)
                        continue
                    case .authorized(let token):
                        try await self.accountService.completeSignIn(token: token.token)
                        self.isDeviceSignInPresented = false
                        self.deviceAuthorization = nil
                        self.accountState = self.accountService.state
                        await self.licensingService.refresh()
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
            await accountService.signOut()
            await licensingService.setSignedIn(false)
            accountState = .signedOut
            licensingState = .signedOut
        }
    }

    func refreshLicense() {
        Task { await licensingService.refresh() }
    }

    /// Reloads persisted data and settings. Called after any structural change.
    func refresh() {
        settings = container.settings
        dataVersion &+= 1
        tracking.snapshot = container.trackingEngine.snapshot()
    }

    func refreshPermissions() {
        permissionStatuses = PermissionKind.allCases.map { permissionProvider.status(for: $0) }
    }

    func permissionStatus(for kind: PermissionKind) -> PermissionState {
        permissionProvider.status(for: kind).state
    }

    func requestPermission(_ kind: PermissionKind) {
        permissionProvider.request(kind)
        refreshPermissions()
    }

    func openSystemSettings(for kind: PermissionKind) {
        permissionProvider.openSystemSettings(for: kind)
    }

    func openPrivacySettings() {
        permissionProvider.openPrivacySettings()
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
        guard canRecordNewSessions else {
            alertMessage = entitlementMessage
            return
        }
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
