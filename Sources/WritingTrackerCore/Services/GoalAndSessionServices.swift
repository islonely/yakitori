import Foundation

public final class GoalService {
    private let database: Database
    private let goalRepository: GoalRepository
    private let statistics: StatisticsService

    public init(database: Database, statistics: StatisticsService) {
        self.database = database
        self.goalRepository = GoalRepository(database: database)
        self.statistics = statistics
    }

    @discardableResult
    public func createGoal(
        period: GoalPeriod,
        metric: GoalMetric = .words,
        target: Double,
        projectID: String? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil
    ) throws -> Goal {
        let goal = Goal(projectID: projectID, period: period, metric: metric, target: target, startDate: startDate, endDate: endDate)
        try goalRepository.insert(goal)
        return goal
    }

    public func update(_ goal: Goal) throws {
        try goalRepository.update(goal)
    }

    public func delete(goalID: String) throws {
        try goalRepository.delete(id: goalID)
    }

    public func allGoals() throws -> [Goal] {
        try goalRepository.all()
    }

    public func enabledGoals() throws -> [Goal] {
        try goalRepository.enabled()
    }

    public func progress() -> [GoalProgress] {
        statistics.goalProgress()
    }

    /// Ensures a sensible default daily goal exists (does not overwrite user goals).
    public func ensureDefaultGoal() throws {
        let existing = try goalRepository.all()
        guard existing.isEmpty else { return }
        try createGoal(period: .daily, metric: .words, target: 500)
    }
}

public final class SessionService {
    private let database: Database
    private let sessionRepository: SessionRepository
    private let projectRepository: ProjectRepository
    private let documentRepository: DocumentRepository
    private let statistics: StatisticsService

    public init(database: Database, statistics: StatisticsService) {
        self.database = database
        self.sessionRepository = SessionRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
        self.statistics = statistics
    }

    public func sessions(filter: SessionFilter) throws -> [Session] {
        try sessionRepository.sessions(filter: filter)
    }

    public func allSessions() throws -> [Session] {
        try sessionRepository.all()
    }

    public func session(id: String) throws -> Session? {
        try sessionRepository.find(id: id)
    }

    public func deleteSession(id: String) throws {
        try sessionRepository.delete(id: id)
        try statistics.rebuildDailyAggregates()
    }

    public func updateSession(_ session: Session) throws {
        try sessionRepository.update(session)
        try rebuildAffected(session)
    }

    public func setNotes(sessionID: String, notes: String?) throws {
        guard var session = try sessionRepository.find(id: sessionID) else { return }
        session.notes = notes
        try sessionRepository.update(session)
    }

    public func setSessionType(sessionID: String, type: SessionType) throws {
        guard var session = try sessionRepository.find(id: sessionID) else { return }
        session.sessionType = type
        try sessionRepository.update(session)
    }

    public func assignProject(sessionID: String, projectID: String?) throws {
        guard var session = try sessionRepository.find(id: sessionID) else { return }
        session.projectID = projectID
        try sessionRepository.update(session)
    }

    public func correctDuration(sessionID: String, activeSeconds: Double) throws {
        guard var session = try sessionRepository.find(id: sessionID) else { return }
        let clamped = max(0, activeSeconds)
        session.activeSeconds = clamped
        if session.endedAt == nil {
            session.endedAt = session.startedAt.addingTimeInterval(clamped)
        }
        // Keep the exact ranges consistent with the corrected duration.
        if clamped == 0 {
            session.activeRanges = []
        } else {
            let end = min(session.startedAt.addingTimeInterval(clamped), session.endedAt ?? session.startedAt.addingTimeInterval(clamped))
            session.activeRanges = end > session.startedAt ? [TimeRange(start: session.startedAt, end: end)] : []
        }
        try sessionRepository.update(session)
        try rebuildAffected(session)
    }

    /// Adds a manually entered writing session (paper, another computer, offline…).
    @discardableResult
    public func addManualSession(
        projectID: String?,
        date: Date,
        words: Int,
        activeSeconds: Double,
        sessionType: SessionType = .drafting,
        notes: String? = nil
    ) throws -> Session {
        let start = date
        let end = start.addingTimeInterval(max(0, activeSeconds))
        let session = Session(
            projectID: projectID,
            documentID: nil,
            applicationID: nil,
            startedAt: start,
            endedAt: end,
            activeSeconds: max(0, activeSeconds),
            focusSeconds: 0,
            startingWordCount: nil,
            endingWordCount: nil,
            wordsAdded: words >= 0 ? words : nil,
            wordsRemoved: words < 0 ? -words : nil,
            netWordChange: words,
            sessionType: sessionType,
            notes: notes,
            activeRanges: activeSeconds > 0 ? [TimeRange(start: start, end: end)] : [],
            focusRanges: [],
            isRecovered: false
        )
        try sessionRepository.insert(session)
        try rebuildAffected(session)
        return session
    }

    private func rebuildAffected(_ session: Session) throws {
        let calendar = statistics.calendar
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        for day in calendar.days(from: start, through: end) {
            _ = statistics.rebuildDailyAggregate(for: day)
        }
    }
}
