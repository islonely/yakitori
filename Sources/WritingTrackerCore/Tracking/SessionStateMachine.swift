import Foundation

/// Session lifecycle states.
public enum SessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case focused
    case active
    case paused
    case ended
}

/// Inputs consumed by the session state machine.
public enum SessionEvent: Equatable, Sendable {
    case startManually(at: Date, type: SessionType)
    case stopManually(at: Date)
    case pauseManually(at: Date)
    case resumeManually(at: Date)
    /// Frontmost application changed. `isTrackedWritingApp` is true when the
    /// frontmost app is an enabled writing application for the current mode.
    case frontmostChanged(at: Date, applicationID: String?, isTrackedWritingApp: Bool)
    case activity(at: Date)
    case inactivityElapsed(at: Date)
    case systemWillSleep(at: Date)
    case systemDidWake(at: Date)
    case documentChanged(documentID: String?, at: Date)
    case wordCountSampled(starting: Int?, ending: Int?, at: Date)
}

/// Policy that determines how the state machine reacts to focus/inactivity.
public struct SessionPolicy: Equatable, Sendable {
    public var mode: TrackingMode
    /// Seconds of inactivity before ACTIVE → PAUSED. `0` means never.
    public var inactivityTimeout: TimeInterval
    /// When true, losing the writing application ends the session.
    public var endOnAppUnfocus: Bool
    /// When true, inactivity ends the session; otherwise it pauses.
    public var endOnInactivity: Bool

    public init(
        mode: TrackingMode,
        inactivityTimeout: TimeInterval,
        endOnAppUnfocus: Bool,
        endOnInactivity: Bool = false
    ) {
        self.mode = mode
        self.inactivityTimeout = inactivityTimeout
        self.endOnAppUnfocus = endOnAppUnfocus
        self.endOnInactivity = endOnInactivity
    }

    public static func policy(for mode: TrackingMode, inactivity: InactivityTimeout) -> SessionPolicy {
        switch mode {
        case .manual:
            return SessionPolicy(mode: .manual, inactivityTimeout: inactivity.seconds, endOnAppUnfocus: false)
        case .automatic:
            // Automatic (unfiltered) treats leaving the writing app as the end of a session.
            return SessionPolicy(mode: .automatic, inactivityTimeout: inactivity.seconds, endOnAppUnfocus: true)
        case .automaticFiltered:
            return SessionPolicy(mode: .automaticFiltered, inactivityTimeout: inactivity.seconds, endOnAppUnfocus: false)
        }
    }
}

public struct SessionTransition: Equatable, Sendable {
    public let from: SessionState
    public let to: SessionState
    public let at: Date
    public let reason: String
}

/// Deterministic, GUI-independent session state machine.
///
/// The machine owns time accounting (active/focus ranges) but performs no
/// persistence. Callers observe transitions and persist the produced session.
public final class SessionStateMachine {
    public private(set) var state: SessionState = .idle
    public private(set) var session: Session?
    public var policy: SessionPolicy

    public var applicationID: String?
    public var documentID: String?
    public var projectID: String?
    public var sessionType: SessionType = .unknown

    public var onTransition: ((SessionTransition) -> Void)?
    /// Called when a new session begins, before any time has accumulated.
    public var onSessionBegan: ((String, Date) -> Void)?

    private var sessionID: String = UUID().uuidString
    private var startedAt: Date?
    private var activeOpen: Date?
    private var focusOpen: Date?
    private var activeSeconds: Double = 0
    private var focusSeconds: Double = 0
    private var activeRanges: [TimeRange] = []
    private var focusRanges: [TimeRange] = []
    private var startingWordCount: Int?
    private var endingWordCount: Int?
    private var isManual = false

    public init(policy: SessionPolicy, sessionType: SessionType = .unknown) {
        self.policy = policy
        self.sessionType = sessionType
    }

    public var isSessionOpen: Bool {
        state != .idle && state != .ended
    }

    public var isFocused: Bool { focusOpen != nil }

    /// Live elapsed accounting for the current session.
    public var liveActiveSeconds: Double { activeSeconds + (activeOpen.map { Date().timeIntervalSince($0) } ?? 0) }
    public var liveFocusSeconds: Double { focusSeconds + (focusOpen.map { Date().timeIntervalSince($0) } ?? 0) }

    public var liveDuration: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    public var currentSessionID: String? { isSessionOpen ? sessionID : nil }

    // MARK: - Event handling

    @discardableResult
    public func handle(_ event: SessionEvent) -> SessionTransition? {
        switch event {
        case .startManually(let at, let type):
            return startManually(at: at, type: type)
        case .stopManually(let at):
            return end(at: at, reason: "manual stop")
        case .pauseManually(let at):
            return pause(at: at, reason: "manual pause", alsoCloseFocus: false)
        case .resumeManually(let at):
            return resume(at: at, reason: "manual resume")
        case .frontmostChanged(let at, let appID, let isTracked):
            return handleFrontmost(at: at, applicationID: appID, isTracked: isTracked)
        case .activity(let at):
            return handleActivity(at: at)
        case .inactivityElapsed(let at):
            return handleInactivity(at: at)
        case .systemWillSleep(let at):
            return handleSleep(at: at)
        case .systemDidWake(let at):
            return handleWake(at: at)
        case .documentChanged(let docID, _):
            documentID = docID
            return nil
        case .wordCountSampled(let starting, let ending, _):
            if startingWordCount == nil, let starting { startingWordCount = starting }
            if let ending { endingWordCount = ending }
            return nil
        }
    }

    // MARK: - Transitions

    private func startManually(at date: Date, type: SessionType) -> SessionTransition? {
        guard state == .idle || state == .ended else { return nil }
        sessionType = type
        isManual = true
        beginSession(at: date)
        openFocus(at: date)
        openActive(at: date)
        return transition(to: .active, at: date, reason: "manual start")
    }

    private func handleFrontmost(at date: Date, applicationID appID: String?, isTracked: Bool) -> SessionTransition? {
        if !isTracked {
            // Non-writing app became frontmost.
            closeFocus(at: date)
            switch state {
            case .active, .focused:
                if policy.endOnAppUnfocus && !isManual {
                    return end(at: date, reason: "writing app unfocused")
                } else {
                    return pause(at: date, reason: "writing app unfocused", alsoCloseFocus: true)
                }
            case .paused:
                return nil
            default:
                return nil
            }
        }

        // A tracked writing application became frontmost.
        applicationID = appID
        switch state {
        case .idle, .ended:
            // Automatic modes auto-start; manual mode requires explicit start.
            if policy.mode == .manual { return nil }
            beginSession(at: date)
            openFocus(at: date)
            return transition(to: .focused, at: date, reason: "writing app focused")
        case .focused:
            openFocus(at: date)
            return nil
        case .active:
            openFocus(at: date)
            return nil
        case .paused:
            openFocus(at: date)
            return nil
        }
    }

    private func handleActivity(at date: Date) -> SessionTransition? {
        switch state {
        case .active:
            return nil
        case .focused, .paused:
            guard isFocused else { return nil }
            if state == .paused { openActive(at: date); return transition(to: .active, at: date, reason: "activity resumed") }
            openActive(at: date)
            return transition(to: .active, at: date, reason: "activity detected")
        default:
            return nil
        }
    }

    private func handleInactivity(at date: Date) -> SessionTransition? {
        switch state {
        case .active:
            if policy.endOnInactivity && !isManual {
                return end(at: date, reason: "inactivity")
            }
            return pause(at: date, reason: "inactivity", alsoCloseFocus: false)
        case .focused:
            // Focused but never produced activity: close an empty session.
            return end(at: date, reason: "inactivity in focus")
        default:
            return nil
        }
    }

    private func handleSleep(at date: Date) -> SessionTransition? {
        guard isSessionOpen else { return nil }
        closeActive(at: date)
        closeFocus(at: date)
        if state == .active || state == .focused {
            return transition(to: .paused, at: date, reason: "system sleep")
        }
        return nil
    }

    private func handleWake(at date: Date) -> SessionTransition? {
        // Remain paused; focus reopens when the engine reports the app frontmost again.
        _ = date
        return nil
    }

    private func pause(at date: Date, reason: String, alsoCloseFocus: Bool) -> SessionTransition? {
        guard state == .active || state == .focused else { return nil }
        closeActive(at: date)
        if alsoCloseFocus { closeFocus(at: date) }
        return transition(to: .paused, at: date, reason: reason)
    }

    private func resume(at date: Date, reason: String) -> SessionTransition? {
        guard state == .paused else { return nil }
        openActive(at: date)
        return transition(to: .active, at: date, reason: reason)
    }

    @discardableResult
    private func end(at date: Date, reason: String) -> SessionTransition? {
        guard isSessionOpen else { return nil }
        closeActive(at: date)
        closeFocus(at: date)
        let built = buildSession(endedAt: date)
        session = built
        let from = state
        state = .ended
        let transition = SessionTransition(from: from, to: .ended, at: date, reason: reason)
        onTransition?(transition)
        resetAfterEnd()
        return transition
    }

    // MARK: - Range management

    private func beginSession(at date: Date) {
        sessionID = UUID().uuidString
        startedAt = date
        activeSeconds = 0
        focusSeconds = 0
        activeRanges = []
        focusRanges = []
        activeOpen = nil
        focusOpen = nil
        startingWordCount = nil
        endingWordCount = nil
        state = .focused
        onSessionBegan?(sessionID, date)
    }

    private func openActive(at date: Date) {
        if activeOpen == nil { activeOpen = date }
    }

    private func closeActive(at date: Date) {
        guard let open = activeOpen else { return }
        activeOpen = nil
        if date > open {
            activeRanges.append(TimeRange(start: open, end: date))
            activeSeconds += date.timeIntervalSince(open)
        }
    }

    private func openFocus(at date: Date) {
        if focusOpen == nil { focusOpen = date }
    }

    private func closeFocus(at date: Date) {
        guard let open = focusOpen else { return }
        focusOpen = nil
        if date > open {
            focusRanges.append(TimeRange(start: open, end: date))
            focusSeconds += date.timeIntervalSince(open)
        }
    }

    private func transition(to newState: SessionState, at date: Date, reason: String) -> SessionTransition? {
        let from = state
        guard from != newState else { return nil }
        state = newState
        let transition = SessionTransition(from: from, to: newState, at: date, reason: reason)
        onTransition?(transition)
        return transition
    }

    /// Returns the currently open session with ranges included up to `date`.
    /// Persisting this periodically enables crash recovery without phantom time.
    public func snapshotSession(at date: Date) -> Session? {
        guard isSessionOpen, let startedAt else { return nil }
        var active = activeRanges
        if let open = activeOpen, date > open { active.append(TimeRange(start: open, end: date)) }
        var focus = focusRanges
        if let open = focusOpen, date > open { focus.append(TimeRange(start: open, end: date)) }
        return Session(
            id: sessionID,
            projectID: projectID,
            documentID: documentID,
            applicationID: applicationID,
            startedAt: startedAt,
            endedAt: nil,
            activeSeconds: active.reduce(0) { $0 + $1.duration },
            focusSeconds: focus.reduce(0) { $0 + $1.duration },
            startingWordCount: startingWordCount,
            endingWordCount: endingWordCount,
            wordsAdded: nil,
            wordsRemoved: nil,
            netWordChange: {
                guard let s = startingWordCount, let e = endingWordCount else { return nil }
                return e - s
            }(),
            sessionType: sessionType,
            notes: nil,
            activeRanges: active,
            focusRanges: focus,
            isRecovered: false
        )
    }

    private func buildSession(endedAt: Date) -> Session {        Session(
            id: sessionID,
            projectID: projectID,
            documentID: documentID,
            applicationID: applicationID,
            startedAt: startedAt ?? endedAt,
            endedAt: endedAt,
            activeSeconds: activeSeconds,
            focusSeconds: focusSeconds,
            startingWordCount: startingWordCount,
            endingWordCount: endingWordCount,
            wordsAdded: nil,
            wordsRemoved: nil,
            netWordChange: {
                guard let s = startingWordCount, let e = endingWordCount else { return nil }
                return e - s
            }(),
            sessionType: sessionType,
            notes: nil,
            activeRanges: activeRanges,
            focusRanges: focusRanges,
            isRecovered: false
        )
    }

    private func resetAfterEnd() {
        startedAt = nil
        activeOpen = nil
        focusOpen = nil
        applicationID = nil
        documentID = nil
        // state stays `.ended` so the caller can distinguish a clean end.
    }

    /// Returns to IDLE so a new automatic session can begin.
    public func resetToIdle() {
        guard state == .ended || state == .idle else { return }
        state = .idle
        session = nil
        isManual = false
        sessionType = .unknown
        projectID = nil
    }

    /// Forces the open session closed, used during crash recovery.
    public func forceCloseForRecovery(at date: Date) {
        guard isSessionOpen else { return }
        _ = end(at: date, reason: "recovery")
    }
}
