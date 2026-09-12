import Foundation
import AppKit

/// Resolves the project a document/application belongs to.
public protocol ProjectResolving: AnyObject {
    func resolveProjectID(documentPath: String?, documentName: String?, applicationID: String?) -> String?
}

/// Live view of the tracking engine for the UI layer.
public struct TrackingSnapshot: Sendable {
    public var state: SessionState
    public var isRunning: Bool
    public var currentProjectID: String?
    public var currentApplicationID: String?
    public var currentApplicationName: String?
    public var currentDocumentName: String?
    public var currentSessionID: String?
    public var currentSessionStartedAt: Date?
    public var currentSessionActiveSeconds: Double
    public var currentSessionFocusSeconds: Double
    public var currentSessionNetWords: Int?
    public var currentSessionType: SessionType
    public var todayNetWords: Int
    public var todayActiveSeconds: Double
    public var todaySessions: Int
    public var lastActivityAt: Date?

    public var isSessionOpen: Bool { state != .idle && state != .ended }

    public static let idle = TrackingSnapshot(
        state: .idle,
        isRunning: false,
        currentProjectID: nil,
        currentApplicationID: nil,
        currentApplicationName: nil,
        currentDocumentName: nil,
        currentSessionID: nil,
        currentSessionStartedAt: nil,
        currentSessionActiveSeconds: 0,
        currentSessionFocusSeconds: 0,
        currentSessionNetWords: nil,
        currentSessionType: .unknown,
        todayNetWords: 0,
        todayActiveSeconds: 0,
        todaySessions: 0,
        lastActivityAt: nil
    )
}

/// The background tracking engine. Completely independent of SwiftUI; it can run
/// with the GUI closed and persists all state through repositories.
public final class TrackingEngine {
    // MARK: Dependencies
    private let database: Database
    private let permissionProvider: PermissionProviding
    private let dateProvider: DateProviding
    private let registry: AdapterRegistry
    private let idleProvider: SystemIdleProviding

    private let sessionRepository: SessionRepository
    private let eventRepository: ActivityEventRepository
    private let snapshotRepository: WordCountSnapshotRepository
    private let applicationRepository: WritingApplicationRepository
    private let documentRepository: DocumentRepository
    private let aggregateRepository: DailyAggregateRepository
    private let settingsRepository: SettingsRepository
    private let projectResolver: ProjectResolving?

    // MARK: Monitors
    private let frontmostMonitor = FrontmostApplicationMonitor()
    private let activityMonitor = ActivityMonitor()
    private let sleepMonitor = SystemSleepMonitor()
    private let timeChangeMonitor = TimeChangeMonitor()

    // MARK: State (accessed only on `queue`)
    private let queue = DispatchQueue(label: "com.writingtracker.engine")
    private var stateMachine: SessionStateMachine
    private var settings: UserSettings = .default
    private var applications: [WritingApplication] = []
    private var currentApplication: WritingApplication?
    private var currentAdapter: WritingApplicationAdapter?
    private var currentDocument: Document?
    private var lastActivityAt: Date?
    private var lastWordCount: Int?
    private var isRunning = false

    private var inactivityTimer: DispatchSourceTimer?
    private var checkpointTimer: DispatchSourceTimer?
    private var wordCountTimer: DispatchSourceTimer?
    private var eventFlushTimer: DispatchSourceTimer?
    private var pendingEvents: [ActivityEvent] = []

    // MARK: Callbacks
    /// Called on the main queue whenever observable tracking state changes.
    public var onChange: (() -> Void)?

    private let wordCountSampleInterval: TimeInterval = 15
    private let idleFallbackInterval: TimeInterval = 5
    private let checkpointInterval: TimeInterval = 20
    private let eventFlushInterval: TimeInterval = 5
    private var currentCalendar: CalendarContext

    // MARK: Init

    public init(
        database: Database,
        permissionProvider: PermissionProviding,
        dateProvider: DateProviding = SystemDateProvider(),
        registry: AdapterRegistry = .shared,
        idleProvider: SystemIdleProviding = CGSystemIdleProvider(),
        projectResolver: ProjectResolving? = nil,
        calendarContext: CalendarContext = CalendarContext()
    ) {
        self.database = database
        self.permissionProvider = permissionProvider
        self.dateProvider = dateProvider
        self.registry = registry
        self.idleProvider = idleProvider
        self.projectResolver = projectResolver
        self.currentCalendar = calendarContext
        self.sessionRepository = SessionRepository(database: database)
        self.eventRepository = ActivityEventRepository(database: database)
        self.snapshotRepository = WordCountSnapshotRepository(database: database)
        self.applicationRepository = WritingApplicationRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
        self.aggregateRepository = DailyAggregateRepository(database: database)
        self.settingsRepository = SettingsRepository(database: database)
        self.settings = (try? settingsRepository.load()) ?? .default
        self.stateMachine = SessionStateMachine(
            policy: SessionPolicy.policy(for: settings.trackingMode, inactivity: settings.inactivityTimeout),
            sessionType: settings.defaultSessionType
        )
        configureStateMachineCallbacks()
    }

    // MARK: Lifecycle

    public func start() {
        queue.sync {
            guard !isRunning else { return }
            isRunning = true
            reloadSettingsLocked()
            recoverOpenSessionsLocked()
            registerMonitors()
            startTimers()
            Log.tracking.info("Tracking engine started (mode: \(self.settings.trackingMode.rawValue, privacy: .public))")
        }
        notifyChange()
    }

    public func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            flushEventsLocked()
            if stateMachine.isSessionOpen {
                checkpointOpenSessionLocked()
            }
            frontmostMonitor.stop()
            activityMonitor.stop()
            sleepMonitor.stop()
            timeChangeMonitor.stop()
            stopTimers()
            Log.tracking.info("Tracking engine stopped")
        }
        notifyChange()
    }

    /// Ends and persists any open session (used on clean quit).
    public func endActiveSession() {
        queue.sync {
            guard stateMachine.isSessionOpen else { return }
            let now = dateProvider.now
            _ = stateMachine.handle(.stopManually(at: now))
            persistEndedSessionLocked()
        }
        notifyChange()
    }

    public func reloadSettings() {
        queue.sync { reloadSettingsLocked() }
        notifyChange()
    }

    // MARK: Manual control

    public func startManualSession(projectID: String?, type: SessionType, documentID: String? = nil) {
        queue.sync {
            guard isRunning else { return }
            if stateMachine.isSessionOpen {
                _ = stateMachine.handle(.stopManually(at: dateProvider.now))
                persistEndedSessionLocked()
            }
            stateMachine.resetToIdle()
            stateMachine.projectID = projectID
            stateMachine.documentID = documentID
            stateMachine.applicationID = currentApplication?.id
            _ = stateMachine.handle(.startManually(at: dateProvider.now, type: type))
            persistOpenSessionLocked()
            flushEventsLocked()
        }
        notifyChange()
    }

    public func pauseSession() {
        queue.sync {
            _ = stateMachine.handle(.pauseManually(at: dateProvider.now))
            checkpointOpenSessionLocked()
        }
        notifyChange()
    }

    public func resumeSession() {
        queue.sync {
            _ = stateMachine.handle(.resumeManually(at: dateProvider.now))
            checkpointOpenSessionLocked()
        }
        notifyChange()
    }

    public func stopSession() {
        queue.sync {
            _ = stateMachine.handle(.stopManually(at: dateProvider.now))
            persistEndedSessionLocked()
        }
        notifyChange()
    }

    public func setCurrentProject(_ projectID: String?) {
        queue.sync {
            stateMachine.projectID = projectID
            if stateMachine.isSessionOpen {
                checkpointOpenSessionLocked()
            }
        }
        notifyChange()
    }

    // MARK: Snapshot

    public func snapshot() -> TrackingSnapshot {
        queue.sync { snapshotLocked() }
    }

    // MARK: - Private: setup

    private func configureStateMachineCallbacks() {
        stateMachine.onSessionBegan = { [weak self] _, _ in
            guard let self else { return }
            self.lastWordCount = nil
            self.recordEventLocked(type: .sessionStarted, at: self.dateProvider.now)
        }
        stateMachine.onTransition = { [weak self] transition in
            guard let self else { return }
            switch transition.to {
            case .paused: self.recordEventLocked(type: .sessionPaused, at: transition.at)
            case .active: self.recordEventLocked(type: .sessionResumed, at: transition.at)
            case .ended:
                self.recordEventLocked(type: .sessionEnded, at: transition.at)
                self.persistEndedSessionLocked()
            default: break
            }
        }
    }

    private func reloadSettingsLocked() {
        settings = (try? settingsRepository.load()) ?? settings
        stateMachine.policy = SessionPolicy.policy(for: settings.trackingMode, inactivity: settings.inactivityTimeout)
        applications = (try? applicationRepository.all()) ?? []
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    private func registerMonitors() {
        frontmostMonitor.onFrontmostChanged = { [weak self] info in
            self?.queue.async { self?.handleFrontmostLocked(info) }
        }
        frontmostMonitor.start()

        activityMonitor.onActivity = { [weak self] date, kind in
            self?.queue.async { self?.handleActivityLocked(at: date, kind: kind, isPoll: false) }
        }
        activityMonitor.start()

        sleepMonitor.onWillSleep = { [weak self] date in
            self?.queue.async { self?.handleSleepLocked(at: date) }
        }
        sleepMonitor.onDidWake = { [weak self] date in
            self?.queue.async { self?.handleWakeLocked(at: date) }
        }
        sleepMonitor.start()

        timeChangeMonitor.onTimeChanged = { [weak self] in
            self?.queue.async {
                self?.currentCalendar = CalendarContext(firstWeekday: self?.settings.weekStart ?? .sunday)
                self?.notifyChange()
            }
        }
        timeChangeMonitor.start()
    }

    private func startTimers() {
        let inactivity = DispatchSource.makeTimerSource(queue: queue)
        inactivity.schedule(deadline: .now() + idleFallbackInterval, repeating: idleFallbackInterval, leeway: .seconds(1))
        inactivity.setEventHandler { [weak self] in self?.tickLocked() }
        inactivity.resume()
        inactivityTimer = inactivity

        let checkpoint = DispatchSource.makeTimerSource(queue: queue)
        checkpoint.schedule(deadline: .now() + checkpointInterval, repeating: checkpointInterval, leeway: .seconds(5))
        checkpoint.setEventHandler { [weak self] in self?.checkpointOpenSessionLocked() }
        checkpoint.resume()
        checkpointTimer = checkpoint

        let events = DispatchSource.makeTimerSource(queue: queue)
        events.schedule(deadline: .now() + eventFlushInterval, repeating: eventFlushInterval, leeway: .seconds(2))
        events.setEventHandler { [weak self] in self?.flushEventsLocked() }
        events.resume()
        eventFlushTimer = events

        let wordCount = DispatchSource.makeTimerSource(queue: queue)
        wordCount.schedule(deadline: .now() + wordCountSampleInterval, repeating: wordCountSampleInterval, leeway: .seconds(3))
        wordCount.setEventHandler { [weak self] in self?.sampleWordCountLocked() }
        wordCount.resume()
        wordCountTimer = wordCount
    }

    private func stopTimers() {
        inactivityTimer?.cancel(); inactivityTimer = nil
        checkpointTimer?.cancel(); checkpointTimer = nil
        wordCountTimer?.cancel(); wordCountTimer = nil
        eventFlushTimer?.cancel(); eventFlushTimer = nil
    }

    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: - Private: event handling

    private func handleFrontmostLocked(_ info: FrontmostApplicationInfo) {
        let tracked = isTrackedWritingApplication(info)
        let application = tracked ? applicationRecord(for: info) : currentApplication
        let previousAppID = stateMachine.applicationID

        if tracked {
            currentApplication = application
            currentAdapter = application.flatMap { registry.adapter(forBundleIdentifier: $0.bundleIdentifier, adapterType: $0.adapterType) }
        } else {
            currentApplication = nil
            currentAdapter = nil
        }

        if tracked != (previousAppID != nil) || (tracked && application?.id != previousAppID) {
            recordEventLocked(type: tracked ? .applicationFocused : .applicationUnfocused, at: dateProvider.now)
        }

        _ = stateMachine.handle(.frontmostChanged(
            at: dateProvider.now,
            applicationID: application?.id,
            isTrackedWritingApp: tracked
        ))

        if tracked, stateMachine.isSessionOpen || stateMachine.state == .ended {
            // A newly started automatic session needs to be persisted.
            if stateMachine.isSessionOpen, !sessionExistsLocked(id: stateMachine.currentSessionID ?? "") {
                persistOpenSessionLocked()
            }
            refreshDocumentLocked()
            sampleWordCountLocked()
        }

        notifyChange()
    }

    private func handleActivityLocked(at date: Date, kind: ActivityEventType, isPoll: Bool) {
        lastActivityAt = date
        if !isPoll {
            recordEventLocked(type: kind, at: date)
        }
        _ = stateMachine.handle(.activity(at: date))
        notifyChange()
    }

    private func handleSleepLocked(at date: Date) {
        _ = stateMachine.handle(.systemWillSleep(at: date))
        recordEventLocked(type: .systemSleep, at: date)
        flushEventsLocked()
        checkpointOpenSessionLocked()
        notifyChange()
    }

    private func handleWakeLocked(at date: Date) {
        recordEventLocked(type: .systemWake, at: date)
        _ = stateMachine.handle(.systemDidWake(at: date))
        // Re-evaluate the frontmost application; remain paused until activity.
        if let current = frontmostMonitor.current, isTrackedWritingApplication(current) {
            _ = stateMachine.handle(.frontmostChanged(
                at: date,
                applicationID: currentApplication?.id ?? applicationRecord(for: current)?.id,
                isTrackedWritingApp: true
            ))
            refreshDocumentLocked()
        }
        notifyChange()
    }

    private func tickLocked() {
        let now = dateProvider.now
        // Fallback activity detection using the system idle counter. This keeps
        // inactivity handling working when Accessibility is not granted.
        let idle = idleProvider.secondsSinceLastInput()
        if idle < idleFallbackInterval {
            if let last = lastActivityAt {
                if now.timeIntervalSince(last) >= idleFallbackInterval {
                    handleActivityLocked(at: now, kind: .keyboardActivity, isPoll: true)
                }
            } else {
                lastActivityAt = now
            }
        }

        let timeout = settings.inactivityTimeout.seconds
        if timeout > 0, stateMachine.state == .active, let last = lastActivityAt,
           now.timeIntervalSince(last) >= timeout {
            _ = stateMachine.handle(.inactivityElapsed(at: now))
            checkpointOpenSessionLocked()
            notifyChange()
        }
    }

    // MARK: - Private: documents & word counts

    private func refreshDocumentLocked() {
        guard let adapter = currentAdapter, adapter.capabilities.activeDocument else {
            return
        }
        guard let info = adapter.activeDocument() else { return }
        let document = resolveDocumentLocked(info: info)
        if document?.id != currentDocument?.id {
            currentDocument = document
            lastWordCount = nil
            stateMachine.documentID = document?.id
            recordEventLocked(type: .documentChanged, at: dateProvider.now)
            if let document {
                try? documentRepository.touch(id: document.id, at: dateProvider.now)
            }
        }
    }

    private func resolveDocumentLocked(info: ActiveDocumentInfo) -> Document? {
        let appID = currentApplication?.id
        var document: Document?
        if let stable = info.stableIdentifier {
            document = try? documentRepository.find(stableIdentifier: stable)
        }
        if document == nil, let path = info.filePath {
            document = try? documentRepository.find(filePath: path)
        }
        if document == nil {
            document = try? documentRepository.find(displayName: info.displayName, applicationID: appID)
        }

        let resolvedProject = projectResolver?.resolveProjectID(
            documentPath: info.filePath ?? info.stableIdentifier,
            documentName: info.displayName,
            applicationID: appID
        ) ?? stateMachine.projectID

        if var existing = document {
            existing.lastSeenAt = dateProvider.now
            existing.displayName = info.displayName
            if existing.filePath == nil { existing.filePath = info.filePath }
            if existing.stableIdentifier == nil { existing.stableIdentifier = info.stableIdentifier }
            if existing.projectID == nil, let resolvedProject { existing.projectID = resolvedProject }
            try? documentRepository.update(existing)
            return existing
        }

        let new = Document(
            projectID: resolvedProject,
            applicationID: appID,
            displayName: info.displayName,
            stableIdentifier: info.stableIdentifier,
            filePath: info.filePath,
            createdAt: dateProvider.now,
            lastSeenAt: dateProvider.now
        )
        try? documentRepository.insert(new)
        return new
    }

    private func sampleWordCountLocked() {
        guard stateMachine.isSessionOpen, let adapter = currentAdapter, adapter.capabilities.wordCount else { return }
        guard let info = adapter.activeDocument(), let wordCount = info.wordCount else { return }
        guard wordCount != lastWordCount else { return }
        lastWordCount = wordCount

        let projectID = currentDocument?.projectID ?? stateMachine.projectID
        let snapshot = WordCountSnapshot(
            timestamp: dateProvider.now,
            documentID: currentDocument?.id,
            projectID: projectID,
            wordCount: wordCount,
            characterCount: info.characterCount,
            pageCount: info.pageCount,
            source: adapter.adapterType.rawValue
        )
        try? snapshotRepository.insert(snapshot)
        recordEventLocked(type: .wordCountSampled, at: dateProvider.now)
        _ = stateMachine.handle(.wordCountSampled(starting: wordCount, ending: wordCount, at: dateProvider.now))

        if let projectID {
            try? ProjectRepository(database: database).updateCurrentWordCount(id: projectID, wordCount: wordCount)
        }
        checkpointOpenSessionLocked()
        notifyChange()
    }

    // MARK: - Private: persistence

    private func persistOpenSessionLocked() {
        guard let snapshot = stateMachine.snapshotSession(at: dateProvider.now) else { return }
        try? sessionRepository.upsert(snapshot)
    }

    private func checkpointOpenSessionLocked() {
        guard stateMachine.isSessionOpen else { return }
        persistOpenSessionLocked()
    }

    private func persistEndedSessionLocked() {
        guard let session = stateMachine.session else { return }
        // Discard trivial focus-only blips that contain no writing time or words.
        let isTrivial = session.activeSeconds < 1 && session.focusSeconds < 1 && (session.netWordChange ?? 0) == 0
        if !isTrivial {
            try? sessionRepository.upsert(session)
            rebuildAggregatesLocked(touching: session)
        }
        stateMachine.resetToIdle()
        flushEventsLocked()
    }

    private func sessionExistsLocked(id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return (try? sessionRepository.find(id: id)) != nil
    }

    private func rebuildAggregatesLocked(touching session: Session) {
        // Rebuild only the days the session touched; sessions remain the source of truth.
        let builder = DailyAggregateBuilder(calendar: currentCalendar)
        let start = session.startedAt
        let end = session.endedAt ?? dateProvider.now
        let days = currentCalendar.days(from: start, through: end)
        for day in days {
            let dayEnd = currentCalendar.endOfDay(for: day)
            let sessions = (try? sessionRepository.sessions(in: DateInterval(start: day, end: dayEnd))) ?? []
            let aggregates = builder.aggregates(for: sessions)
            if let aggregate = aggregates.first {
                try? aggregateRepository.upsert(aggregate)
            } else {
                let dayKey = currentCalendar.dayKey(for: day)
                try? aggregateRepository.upsert(DailyAggregate(
                    dayKey: dayKey, date: currentCalendar.startOfDay(for: day)
                ))
            }
        }
    }

    private func snapshotLocked() -> TrackingSnapshot {
        let open = stateMachine.snapshotSession(at: dateProvider.now)
        let dayKey = currentCalendar.dayKey(for: dateProvider.now)
        let today = (try? aggregateRepository.find(dayKey: dayKey))
        return TrackingSnapshot(
            state: stateMachine.state,
            isRunning: isRunning,
            currentProjectID: stateMachine.projectID ?? currentDocument?.projectID,
            currentApplicationID: currentApplication?.id,
            currentApplicationName: currentApplication?.displayName,
            currentDocumentName: currentDocument?.displayName,
            currentSessionID: stateMachine.currentSessionID,
            currentSessionStartedAt: open?.startedAt,
            currentSessionActiveSeconds: open?.activeSeconds ?? 0,
            currentSessionFocusSeconds: open?.focusSeconds ?? 0,
            currentSessionNetWords: open?.netWordChange,
            currentSessionType: stateMachine.sessionType,
            todayNetWords: today?.netWords ?? 0,
            todayActiveSeconds: today?.activeSeconds ?? 0,
            todaySessions: today?.sessionCount ?? 0,
            lastActivityAt: lastActivityAt
        )
    }

    // MARK: - Private: activity events

    private func recordEventLocked(type: ActivityEventType, at date: Date) {
        let event = ActivityEvent(
            timestamp: date,
            applicationID: currentApplication?.id,
            eventType: type,
            sessionID: stateMachine.currentSessionID
        )
        pendingEvents.append(event)
        if pendingEvents.count >= 50 { flushEventsLocked() }
    }

    private func flushEventsLocked() {
        guard !pendingEvents.isEmpty else { return }
        let events = pendingEvents
        pendingEvents = []
        try? eventRepository.insertBatch(events)
    }

    // MARK: - Private: crash recovery

    /// Closes sessions left open by a crash without counting time the tracker
    /// was not actually running.
    func recoverOpenSessions() {
        queue.sync { recoverOpenSessionsLocked() }
    }

    private func recoverOpenSessionsLocked() {
        guard let open = try? sessionRepository.openSessions(), !open.isEmpty else { return }
        for var session in open {
            let lastKnown = session.activeRanges.map(\.end).max()
                ?? session.focusRanges.map(\.end).max()
                ?? session.startedAt
            let end = min(max(lastKnown, session.startedAt), dateProvider.now)
            session.endedAt = end
            session.isRecovered = true
            try? sessionRepository.upsert(session)
            Log.tracking.warning("Recovered open session started at \(session.startedAt, privacy: .public)")
        }
        let builder = DailyAggregateBuilder(calendar: currentCalendar)
        if let all = try? sessionRepository.all() {
            try? aggregateRepository.replaceAll(builder.aggregates(for: all))
        }
    }

    // MARK: - Private: application matching

    private func isTrackedWritingApplication(_ info: FrontmostApplicationInfo) -> Bool {
        guard let bundleID = info.bundleIdentifier else { return false }
        if bundleID == Bundle.main.bundleIdentifier { return false }
        guard let application = applications.first(where: { $0.bundleIdentifier == bundleID }), application.enabled else {
            return false
        }
        // When "start at launch" is disabled, automatic sessions wait until the
        // user starts one manually; otherwise the app would track silently.
        if !settings.startTrackingAtLaunch, !stateMachine.isSessionOpen, settings.trackingMode != .manual {
            return false
        }
        switch settings.trackingMode {
        case .manual:
            return settings.selectedApplicationIDs.contains(application.id)
                || settings.selectedApplicationIDs.isEmpty
        case .automatic:
            return true
        case .automaticFiltered:
            return settings.selectedApplicationIDs.isEmpty || settings.selectedApplicationIDs.contains(application.id)
        }
    }

    private func applicationRecord(for info: FrontmostApplicationInfo) -> WritingApplication? {
        guard let bundleID = info.bundleIdentifier else { return nil }
        if let existing = applications.first(where: { $0.bundleIdentifier == bundleID }) {
            return existing
        }
        // Register a newly seen writing application automatically.
        let type = AdapterRegistry.defaultAdapterType(forBundleIdentifier: bundleID)
        let record = WritingApplication(
            bundleIdentifier: bundleID,
            displayName: info.localizedName,
            adapterType: type
        )
        try? applicationRepository.upsert(record)
        applications = (try? applicationRepository.all()) ?? applications
        return applications.first(where: { $0.bundleIdentifier == bundleID }) ?? record
    }
}
