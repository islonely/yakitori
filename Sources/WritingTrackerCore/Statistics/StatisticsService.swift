import Foundation

/// Dedicated statistics engine. The UI must never compute statistics directly
/// from raw records; it calls these APIs.
public final class StatisticsService {
    private let database: Database
    private let dateProvider: DateProviding
    private let aggregateRepository: DailyAggregateRepository
    private let sessionRepository: SessionRepository
    private let projectRepository: ProjectRepository
    private let milestoneRepository: MilestoneRepository
    private let goalRepository: GoalRepository

    public private(set) var settings: UserSettings
    public private(set) var calendar: CalendarContext

    public init(
        database: Database,
        dateProvider: DateProviding = SystemDateProvider(),
        calendarContext: CalendarContext = CalendarContext(),
        settings: UserSettings? = nil
    ) {
        self.database = database
        self.dateProvider = dateProvider
        self.calendar = calendarContext
        self.aggregateRepository = DailyAggregateRepository(database: database)
        self.sessionRepository = SessionRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.milestoneRepository = MilestoneRepository(database: database)
        self.goalRepository = GoalRepository(database: database)
        self.settings = settings ?? (try? SettingsRepository(database: database).load()) ?? .default
    }

    public func refreshSettings() {
        settings = (try? SettingsRepository(database: database).load()) ?? settings
        calendar = CalendarContext(firstWeekday: settings.weekStart)
    }

    // MARK: - Daily

    public func dailyStatistics(date: Date) -> DailyStatistics {
        let dayKey = calendar.dayKey(for: date)
        if let aggregate = try? aggregateRepository.find(dayKey: dayKey) {
            return DailyStatistics(aggregate: aggregate)
        }
        return DailyStatistics(aggregate: DailyAggregate(dayKey: dayKey, date: calendar.startOfDay(for: date)))
    }

    public func dailyStatistics(from start: Date, to end: Date) -> [DailyStatistics] {
        let aggregates = (try? aggregateRepository.aggregates(from: calendar.startOfDay(for: start), to: calendar.endOfDay(for: end))) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.dayKey, $0) })
        return calendar.days(from: start, through: end).map { day in
            let key = calendar.dayKey(for: day)
            if let aggregate = byKey[key] {
                return DailyStatistics(aggregate: aggregate)
            }
            return DailyStatistics(aggregate: DailyAggregate(dayKey: key, date: calendar.startOfDay(for: day)))
        }
    }

    // MARK: - Periods

    public func weeklyStatistics(containing date: Date) -> PeriodStatistics {
        let start = calendar.startOfWeek(for: date)
        let end = calendar.addingDays(7, to: start)
        return periodStatistics(start: start, end: end)
    }

    public func weeklyStatistics(startDate: Date) -> PeriodStatistics {
        periodStatistics(start: calendar.startOfDay(for: startDate), end: calendar.addingDays(7, to: calendar.startOfDay(for: startDate)))
    }

    public func monthlyStatistics(containing date: Date) -> PeriodStatistics {
        let start = calendar.startOfMonth(for: date)
        let end = calendar.calendar.date(byAdding: .month, value: 1, to: start) ?? calendar.addingDays(31, to: start)
        return periodStatistics(start: start, end: end)
    }

    public func yearlyStatistics(year: Int) -> PeriodStatistics {
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        let start = calendar.calendar.date(from: comps) ?? Date()
        let end = calendar.calendar.date(byAdding: .year, value: 1, to: start) ?? calendar.addingDays(365, to: start)
        return periodStatistics(start: start, end: end)
    }

    public func periodStatistics(start: Date, end: Date) -> PeriodStatistics {
        let days = calendar.days(from: start, through: calendar.addingDays(-1, to: end))
        let aggregates = (try? aggregateRepository.aggregates(from: calendar.startOfDay(for: start), to: end)) ?? []
        return buildPeriod(start: start, end: end, days: days, aggregates: aggregates)
    }

    // MARK: - Project

    public func projectStatistics(projectID: String) throws -> ProjectStatistics {
        guard let project = try projectRepository.find(id: projectID) else {
            throw WritingTrackerError.notFound("Project \(projectID)")
        }
        let sessions = (try? sessionRepository.sessions(forProject: projectID)) ?? []
        return buildProjectStatistics(project: project, sessions: sessions)
    }

    public func projectStatistics(project: Project, sessions: [Session]) -> ProjectStatistics {
        buildProjectStatistics(project: project, sessions: sessions)
    }

    // MARK: - Lifetime

    public func lifetimeStatistics() -> LifetimeStatistics {
        let aggregates = (try? aggregateRepository.all()) ?? []
        let sessions = (try? sessionRepository.completed()) ?? []
        let projects = (try? projectRepository.all()) ?? []

        let writingDays = aggregates.filter { isWritingDay($0, threshold: settings.streakThresholdWords) }.count
        let netWords = aggregates.reduce(0) { $0 + $1.netWords }
        let added = aggregates.reduce(0) { $0 + $1.wordsAdded }
        let removed = aggregates.reduce(0) { $0 + $1.wordsRemoved }
        let active = aggregates.reduce(0.0) { $0 + $1.activeSeconds }
        let focus = aggregates.reduce(0.0) { $0 + $1.focusSeconds }

        let bestDayAggregate = aggregates.max { $0.netWords < $1.netWords }
        let bestDay = bestDayAggregate.flatMap { $0.sessionCount > 0 ? BestDay(date: $0.date, words: $0.netWords) : nil }

        let bestSession = sessions.filter { ($0.netWordChange ?? 0) > 0 }.max { ($0.netWordChange ?? 0) < ($1.netWordChange ?? 0) }
        let bestWPM = sessions.compactMap(\.wordsPerMinute).filter { $0 > 0 }.max()
        let bestPerHour = sessions.compactMap { session -> Double? in
            guard session.activeSeconds > 0, let net = session.netWordChange else { return nil }
            return Double(net) / (session.activeSeconds / 3600)
        }.max()
        let longestSession = sessions.map(\.duration).max() ?? 0

        var yearTotals: [String: Int] = [:]
        var monthTotals: [String: Int] = [:]
        for aggregate in aggregates {
            yearTotals[calendar.yearKey(for: aggregate.date), default: 0] += aggregate.netWords
            monthTotals[calendar.monthKey(for: aggregate.date), default: 0] += aggregate.netWords
        }

        let streaks = streakStatistics()
        let first = sessions.map(\.startedAt).min()

        return LifetimeStatistics(
            lifetimeNetWords: netWords,
            wordsAdded: added,
            wordsRemoved: removed,
            writingDays: writingDays,
            totalActiveSeconds: active,
            totalFocusSeconds: focus,
            totalSessions: sessions.count,
            projectCount: projects.count,
            completedProjects: projects.filter { $0.status.isCompleted }.count,
            bestDay: bestDay,
            bestSessionWords: bestSession?.netWordChange,
            bestSessionID: bestSession?.id,
            bestWordsPerMinute: bestWPM,
            bestWordsPerHour: bestPerHour,
            longestStreak: streaks.longestStreak,
            currentStreak: streaks.currentStreak,
            averageWordsPerDay: writingDays > 0 ? Double(netWords) / Double(writingDays) : 0,
            averageWordsPerSession: sessions.isEmpty ? 0 : Double(netWords) / Double(sessions.count),
            firstTrackedDay: first,
            mostProductiveYear: yearTotals.max { $0.value < $1.value }?.key,
            mostProductiveMonth: monthTotals.max { $0.value < $1.value }?.key,
            longestSessionSeconds: longestSession
        )
    }

    // MARK: - Streaks

    public func streakStatistics() -> StreakStatistics {
        let threshold = settings.streakThresholdWords
        let aggregates = (try? aggregateRepository.all()) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.dayKey, $0) })
        let scheduled = settings.writingSchedule.filter(\.enabled).map(\.weekday)
        let today = calendar.startOfDay(for: dateProvider.now)
        let firstDate = aggregates.map(\.date).min() ?? today

        var longest = 0
        var running = 0
        for day in calendar.days(from: firstDate, through: today) {
            let weekday = calendar.weekday(of: day)
            let scheduledDay = scheduled.isEmpty || scheduled.contains(weekday)
            let aggregate = byKey[calendar.dayKey(for: day)]
            let writes = aggregate.map { isWritingDay($0, threshold: threshold) } ?? false
            if !scheduledDay { continue }
            if writes {
                running += 1
                longest = max(longest, running)
            } else if calendar.startOfDay(for: day) == today {
                // Today is still in progress and cannot break the streak yet.
                continue
            } else {
                running = 0
            }
        }

        // Current streak: walk backwards, skipping scheduled days off.
        var current = 0
        var cursor = today
        var guardCount = 0
        while guardCount < 100_000 {
            guardCount += 1
            let weekday = calendar.weekday(of: cursor)
            let scheduledDay = scheduled.isEmpty || scheduled.contains(weekday)
            let aggregate = byKey[calendar.dayKey(for: cursor)]
            let writes = aggregate.map { isWritingDay($0, threshold: threshold) } ?? false
            if scheduledDay {
                if writes {
                    current += 1
                } else if cursor == today {
                    // in progress; continue to yesterday
                } else {
                    break
                }
            }
            guard let previous = calendar.calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: previous)
            if cursor < firstDate { break }
        }

        let lastWriting = aggregates
            .filter { isWritingDay($0, threshold: threshold) }
            .map(\.date)
            .max()

        return StreakStatistics(
            currentStreak: current,
            longestStreak: longest,
            thresholdWords: threshold,
            lastWritingDay: lastWriting,
            scheduledWeekdays: scheduled
        )
    }

    // MARK: - Patterns

    public func productivityPatterns() -> ProductivityPatterns {
        let sessions = (try? sessionRepository.completed()) ?? []
        var hourWords: [Int: Int] = [:]
        var hourSeconds: [Int: Double] = [:]
        var hourSessions: [Int: Int] = [:]
        var weekdayWords: [Int: Int] = [:]
        var weekdaySeconds: [Int: Double] = [:]
        var weekdaySessions: [Int: Int] = [:]

        for session in sessions {
            let startHour = calendar.hour(of: session.startedAt)
            let weekday = calendar.weekday(of: session.startedAt)
            let net = session.netWordChange ?? 0
            hourWords[startHour, default: 0] += net
            hourSessions[startHour, default: 0] += 1
            weekdayWords[weekday, default: 0] += net
            weekdaySessions[weekday, default: 0] += 1
            for range in session.activeRanges {
                // Split each active range across hour boundaries.
                var cursor = range.start
                while cursor < range.end {
                    let hourStart = calendar.calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                    let hourEnd = calendar.calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? range.end
                    let sliceEnd = min(hourEnd, range.end)
                    let seconds = sliceEnd.timeIntervalSince(cursor)
                    let hour = calendar.hour(of: cursor)
                    hourSeconds[hour, default: 0] += seconds
                    weekdaySeconds[weekday, default: 0] += seconds
                    cursor = sliceEnd
                }
            }
        }

        let hours = (0..<24).map { hour in
            HourPattern(
                hour: hour,
                netWords: hourWords[hour] ?? 0,
                activeSeconds: hourSeconds[hour] ?? 0,
                sessions: hourSessions[hour] ?? 0
            )
        }
        let weekdays = (1...7).map { weekday in
            let words = weekdayWords[weekday] ?? 0
            let count = weekdaySessions[weekday] ?? 0
            return WeekdayPattern(
                weekday: weekday,
                netWords: words,
                activeSeconds: weekdaySeconds[weekday] ?? 0,
                sessions: count,
                averageWords: count > 0 ? Double(words) / Double(count) : 0
            )
        }

        let totalActive = sessions.reduce(0.0) { $0 + $1.activeSeconds }
        let totalWords = sessions.reduce(0) { $0 + ($1.netWordChange ?? 0) }
        let sufficient = sessions.count >= 5 || sessions.map(\.startedAt).map { calendar.dayKey(for: $0) }.reduce(into: Set<String>()) { $0.insert($1) }.count >= 3

        return ProductivityPatterns(
            byHour: hours,
            byWeekday: weekdays,
            bestHour: hours.max { $0.netWords < $1.netWords }.flatMap { $0.netWords > 0 ? $0.hour : nil },
            bestWeekday: weekdays.max { $0.netWords < $1.netWords }.flatMap { $0.netWords > 0 ? $0.weekday : nil },
            averageSessionSeconds: sessions.isEmpty ? 0 : totalActive / Double(sessions.count),
            averageSessionWords: sessions.isEmpty ? 0 : Double(totalWords) / Double(sessions.count),
            hasSufficientData: sufficient
        )
    }

    // MARK: - Aggregates

    /// Rebuilds every daily aggregate from raw sessions. Safe to call at any time.
    @discardableResult
    public func rebuildDailyAggregates() -> Int {
        let sessions = (try? sessionRepository.all()) ?? []
        let builder = DailyAggregateBuilder(calendar: calendar)
        let aggregates = builder.aggregates(for: sessions)
        try? aggregateRepository.replaceAll(aggregates)
        Log.statistics.info("Rebuilt \(aggregates.count, privacy: .public) daily aggregates")
        return aggregates.count
    }

    /// Rebuilds aggregates for a single day only.
    @discardableResult
    public func rebuildDailyAggregate(for date: Date) -> DailyAggregate {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.endOfDay(for: dayStart)
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: dayStart, end: dayEnd))) ?? []
        let builder = DailyAggregateBuilder(calendar: calendar)
        let aggregate = builder.aggregate(for: sessions, on: dayStart)
        try? aggregateRepository.upsert(aggregate)
        return aggregate
    }

    // MARK: - Goals

    public func goalProgress() -> [GoalProgress] {
        let goals = (try? goalRepository.enabled()) ?? []
        let now = dateProvider.now
        return goals.compactMap { goal in
            guard let value = currentValue(for: goal, at: now) else { return nil }
            let fraction = goal.target > 0 ? min(1.0, value / goal.target) : 0
            return GoalProgress(goal: goal, currentValue: value, fraction: fraction, isComplete: value >= goal.target)
        }
    }

    public func currentValue(for goal: Goal, at date: Date) -> Double? {
        switch goal.period {
        case .daily:
            let stat = dailyStatistics(date: date)
            return metricValue(goal.metric, netWords: stat.netWords, activeSeconds: stat.activeSeconds, sessions: stat.sessionCount)
        case .weekly:
            let stat = weeklyStatistics(containing: date)
            return metricValue(goal.metric, netWords: stat.netWords, activeSeconds: stat.activeSeconds, sessions: stat.sessions)
        case .monthly:
            let stat = monthlyStatistics(containing: date)
            return metricValue(goal.metric, netWords: stat.netWords, activeSeconds: stat.activeSeconds, sessions: stat.sessions)
        case .project:
            guard let projectID = goal.projectID, let project = try? projectRepository.find(id: projectID) else { return nil }
            return metricValue(goal.metric, netWords: project.currentWordCount, activeSeconds: 0, sessions: 0)
        case .deadline:
            guard let projectID = goal.projectID, let project = try? projectRepository.find(id: projectID) else { return nil }
            return Double(project.currentWordCount)
        }
    }

    private func metricValue(_ metric: GoalMetric, netWords: Int, activeSeconds: Double, sessions: Int) -> Double {
        switch metric {
        case .words: return Double(netWords)
        case .activeMinutes: return activeSeconds / 60
        case .sessions: return Double(sessions)
        }
    }

    // MARK: - Helpers

    func isWritingDay(_ aggregate: DailyAggregate, threshold: Int) -> Bool {
        guard aggregate.sessionCount > 0 else { return false }
        if threshold <= 0 {
            return aggregate.netWords != 0 || aggregate.activeSeconds > 0
        }
        return aggregate.netWords >= threshold
    }

    private func buildPeriod(start: Date, end: Date, days: [Date], aggregates: [DailyAggregate]) -> PeriodStatistics {
        let byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.dayKey, $0) })
        var netWords = 0, added = 0, removed = 0, sessions = 0, writingDays = 0, scheduledDays = 0
        var active = 0.0, focus = 0.0
        var bestDay: BestDay?

        for day in days {
            let weekday = calendar.weekday(of: day)
            if settings.isScheduledDay(weekday: weekday) { scheduledDays += 1 }
            guard let aggregate = byKey[calendar.dayKey(for: day)] else { continue }
            netWords += aggregate.netWords
            added += aggregate.wordsAdded
            removed += aggregate.wordsRemoved
            sessions += aggregate.sessionCount
            active += aggregate.activeSeconds
            focus += aggregate.focusSeconds
            if isWritingDay(aggregate, threshold: settings.streakThresholdWords) { writingDays += 1 }
            if aggregate.sessionCount > 0, bestDay == nil || aggregate.netWords > bestDay!.words {
                bestDay = BestDay(date: aggregate.date, words: aggregate.netWords)
            }
        }

        let divisor = scheduledDays > 0 ? scheduledDays : max(1, days.count)
        let wordGoal = (try? goalRepository.enabled())?.first {
            $0.metric == .words && periodMatches($0.period, start: start, end: end)
        }
        let goalCompletion = wordGoal.flatMap { $0.target > 0 ? Double(netWords) / $0.target : nil }

        return PeriodStatistics(
            startDate: start,
            endDate: end,
            netWords: netWords,
            wordsAdded: added,
            wordsRemoved: removed,
            activeSeconds: active,
            focusSeconds: focus,
            sessions: sessions,
            writingDays: writingDays,
            scheduledDays: scheduledDays,
            averageWordsPerDay: divisor > 0 ? Double(netWords) / Double(divisor) : 0,
            averageWordsPerSession: sessions > 0 ? Double(netWords) / Double(sessions) : 0,
            bestDay: bestDay,
            currentStreak: streakStatistics().currentStreak,
            longestStreak: streakStatistics().longestStreak,
            goalCompletion: goalCompletion
        )
    }

    private func periodMatches(_ period: GoalPeriod, start: Date, end: Date) -> Bool {
        switch period {
        case .daily: return calendar.daysBetween(start, end) <= 1
        case .weekly: return calendar.daysBetween(start, end) <= 7
        case .monthly: return calendar.daysBetween(start, end) <= 31
        default: return false
        }
    }

    private func buildProjectStatistics(project: Project, sessions: [Session]) -> ProjectStatistics {
        let completed = sessions.filter { $0.endedAt != nil }
        let net = completed.reduce(0) { $0 + ($1.netWordChange ?? 0) }
        let added = completed.reduce(0) { $0 + ($1.wordsAdded ?? 0) }
        let removed = completed.reduce(0) { $0 + ($1.wordsRemoved ?? 0) }
        let active = completed.reduce(0.0) { $0 + $1.activeSeconds }
        let writingDays = Set(completed.map { calendar.dayKey(for: $0.startedAt) }).count
        let first = completed.map(\.startedAt).min()
        let last = completed.map { $0.endedAt ?? $0.startedAt }.max()

        let now = dateProvider.now
        let daySpan = max(1, calendar.daysBetween(first ?? project.createdAt, now) + 1)
        let projectPace = Double(max(0, project.netWordChange)) / Double(daySpan)
        let weekPace = pace(for: completed, since: calendar.addingDays(-7, to: now), until: now, divisor: 7)
        let monthPace = pace(for: completed, since: calendar.addingDays(-30, to: now), until: now, divisor: 30)

        var projections: [CompletionProjection] = []
        if let target = project.targetWordCount {
            let remaining = max(0, target - project.currentWordCount)
            projections = [
                makeProjection(label: "7-day pace", pace: weekPace, remaining: remaining, now: now),
                makeProjection(label: "30-day pace", pace: monthPace, remaining: remaining, now: now),
                makeProjection(label: "Project average", pace: projectPace, remaining: remaining, now: now)
            ]
        }

        return ProjectStatistics(
            project: project,
            netWords: net,
            wordsAdded: added,
            wordsRemoved: removed,
            totalActiveSeconds: active,
            sessionCount: completed.count,
            writingDays: writingDays,
            averageWordsPerDay: writingDays > 0 ? Double(net) / Double(writingDays) : 0,
            averageWordsPerSession: completed.isEmpty ? 0 : Double(net) / Double(completed.count),
            lastActivity: last,
            projections: projections
        )
    }

    private func pace(for sessions: [Session], since start: Date, until end: Date, divisor: Int) -> Double {
        let total = sessions
            .filter { $0.startedAt >= start && $0.startedAt <= end }
            .reduce(0) { $0 + ($1.netWordChange ?? 0) }
        return Double(max(0, total)) / Double(max(1, divisor))
    }

    private func makeProjection(label: String, pace: Double, remaining: Int, now: Date) -> CompletionProjection {
        guard pace > 0, remaining > 0 else {
            return CompletionProjection(label: label, wordsPerDay: pace, projectedDate: nil, daysRemaining: nil, isSufficient: false)
        }
        let days = Int(ceil(Double(remaining) / pace))
        let date = calendar.addingDays(days, to: now)
        return CompletionProjection(label: label, wordsPerDay: pace, projectedDate: date, daysRemaining: days, isSufficient: true)
    }
}
