import Foundation

public final class DailyAggregateRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func upsert(_ aggregate: DailyAggregate) throws {
        try database.execute("""
        INSERT INTO daily_aggregates (day_key, date, words_added, words_removed, net_words,
            active_seconds, focus_seconds, session_count, project_count, first_session_at, last_session_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(day_key) DO UPDATE SET
            date=excluded.date, words_added=excluded.words_added, words_removed=excluded.words_removed,
            net_words=excluded.net_words, active_seconds=excluded.active_seconds,
            focus_seconds=excluded.focus_seconds, session_count=excluded.session_count,
            project_count=excluded.project_count, first_session_at=excluded.first_session_at,
            last_session_at=excluded.last_session_at;
        """, [
            .text(aggregate.dayKey), .date(aggregate.date),
            .integer(Int64(aggregate.wordsAdded)), .integer(Int64(aggregate.wordsRemoved)),
            .integer(Int64(aggregate.netWords)), .real(aggregate.activeSeconds),
            .real(aggregate.focusSeconds), .integer(Int64(aggregate.sessionCount)),
            .integer(Int64(aggregate.projectCount)),
            .date(aggregate.firstSessionAt), .date(aggregate.lastSessionAt)
        ])
    }

    public func replaceAll(_ aggregates: [DailyAggregate]) throws {
        try database.transaction {
            try database.execute("DELETE FROM daily_aggregates;")
            for aggregate in aggregates { try upsert(aggregate) }
        }
    }

    public func find(dayKey: String) throws -> DailyAggregate? {
        try database.queryOne("SELECT * FROM daily_aggregates WHERE day_key = ?;", [.text(dayKey)]).map(Self.map)
    }

    public func all() throws -> [DailyAggregate] {
        try database.query("SELECT * FROM daily_aggregates ORDER BY date;").map(Self.map)
    }

    public func aggregates(from start: Date, to end: Date) throws -> [DailyAggregate] {
        try database.query(
            "SELECT * FROM daily_aggregates WHERE date >= ? AND date < ? ORDER BY date;",
            [.date(start), .date(end)]
        ).map(Self.map)
    }

    public func deleteAll() throws { try database.execute("DELETE FROM daily_aggregates;") }

    static func map(_ row: Row) -> DailyAggregate {
        DailyAggregate(
            dayKey: row.string("day_key") ?? "",
            date: row.date("date") ?? Date(),
            wordsAdded: row.int("words_added") ?? 0,
            wordsRemoved: row.int("words_removed") ?? 0,
            netWords: row.int("net_words") ?? 0,
            activeSeconds: row.double("active_seconds") ?? 0,
            focusSeconds: row.double("focus_seconds") ?? 0,
            sessionCount: row.int("session_count") ?? 0,
            projectCount: row.int("project_count") ?? 0,
            firstSessionAt: row.date("first_session_at"),
            lastSessionAt: row.date("last_session_at")
        )
    }
}

public final class GoalRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ goal: Goal) throws {
        try database.execute("""
        INSERT INTO goals (id, project_id, period, metric, target, start_date, end_date, enabled, created_at)
        VALUES (?,?,?,?,?,?,?,?,?);
        """, [
            .text(goal.id), goal.projectID.map { .text($0) } ?? .null,
            .text(goal.period.rawValue), .text(goal.metric.rawValue), .real(goal.target),
            .date(goal.startDate), .date(goal.endDate), .bool(goal.enabled), .date(goal.createdAt)
        ])
    }

    public func update(_ goal: Goal) throws {
        try database.execute("""
        UPDATE goals SET project_id=?, period=?, metric=?, target=?, start_date=?, end_date=?,
            enabled=?, created_at=? WHERE id=?;
        """, [
            goal.projectID.map { .text($0) } ?? .null,
            .text(goal.period.rawValue), .text(goal.metric.rawValue), .real(goal.target),
            .date(goal.startDate), .date(goal.endDate), .bool(goal.enabled), .date(goal.createdAt),
            .text(goal.id)
        ])
    }

    public func upsert(_ goal: Goal) throws {
        if try find(id: goal.id) != nil { try update(goal) } else { try insert(goal) }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM goals WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> Goal? {
        try database.queryOne("SELECT * FROM goals WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    public func all() throws -> [Goal] {
        try database.query("SELECT * FROM goals ORDER BY created_at;").map(Self.map)
    }

    public func enabled() throws -> [Goal] {
        try database.query("SELECT * FROM goals WHERE enabled = 1 ORDER BY created_at;").map(Self.map)
    }

    public func goals(forProject projectID: String) throws -> [Goal] {
        try database.query("SELECT * FROM goals WHERE project_id = ?;", [.text(projectID)]).map(Self.map)
    }

    static func map(_ row: Row) -> Goal {
        Goal(
            id: row.string("id") ?? UUID().uuidString,
            projectID: row.string("project_id"),
            period: GoalPeriod(rawValue: row.string("period") ?? "daily") ?? .daily,
            metric: GoalMetric(rawValue: row.string("metric") ?? "words") ?? .words,
            target: row.double("target") ?? 0,
            startDate: row.date("start_date") ?? Date(),
            endDate: row.date("end_date"),
            enabled: row.bool("enabled") ?? true,
            createdAt: row.date("created_at") ?? Date()
        )
    }
}

public final class MilestoneRepository {
    private let database: Database
    public init(database: Database) { self.database = database }

    public func insert(_ milestone: Milestone) throws {
        try database.execute("""
        INSERT INTO milestones (id, project_id, title, target_value, metric, completed_at, created_at)
        VALUES (?,?,?,?,?,?,?);
        """, [
            .text(milestone.id), .text(milestone.projectID), .text(milestone.title),
            milestone.targetValue.map { .real($0) } ?? .null,
            milestone.metric.map { .text($0.rawValue) } ?? .null,
            .date(milestone.completedAt), .date(milestone.createdAt)
        ])
    }

    public func update(_ milestone: Milestone) throws {
        try database.execute("""
        UPDATE milestones SET project_id=?, title=?, target_value=?, metric=?, completed_at=?, created_at=?
        WHERE id=?;
        """, [
            .text(milestone.projectID), .text(milestone.title),
            milestone.targetValue.map { .real($0) } ?? .null,
            milestone.metric.map { .text($0.rawValue) } ?? .null,
            .date(milestone.completedAt), .date(milestone.createdAt), .text(milestone.id)
        ])
    }

    public func upsert(_ milestone: Milestone) throws {
        if try find(id: milestone.id) != nil { try update(milestone) } else { try insert(milestone) }
    }

    public func delete(id: String) throws {
        try database.execute("DELETE FROM milestones WHERE id = ?;", [.text(id)])
    }

    public func find(id: String) throws -> Milestone? {
        try database.queryOne("SELECT * FROM milestones WHERE id = ?;", [.text(id)]).map(Self.map)
    }

    public func all() throws -> [Milestone] {
        try database.query("SELECT * FROM milestones ORDER BY created_at;").map(Self.map)
    }

    public func milestones(forProject projectID: String) throws -> [Milestone] {
        try database.query(
            "SELECT * FROM milestones WHERE project_id = ? ORDER BY COALESCE(target_value, 0);",
            [.text(projectID)]
        ).map(Self.map)
    }

    public func completedCount() throws -> Int {
        try database.scalar("SELECT COUNT(*) FROM milestones WHERE completed_at IS NOT NULL;")?.intValue ?? 0
    }

    static func map(_ row: Row) -> Milestone {
        Milestone(
            id: row.string("id") ?? UUID().uuidString,
            projectID: row.string("project_id") ?? "",
            title: row.string("title") ?? "",
            targetValue: row.double("target_value"),
            metric: row.string("metric").flatMap { GoalMetric(rawValue: $0) },
            completedAt: row.date("completed_at"),
            createdAt: row.date("created_at") ?? Date()
        )
    }
}
