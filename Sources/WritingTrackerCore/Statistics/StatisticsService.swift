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
    private let snapshotRepository: WordCountSnapshotRepository

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
        self.snapshotRepository = WordCountSnapshotRepository(database: database)
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

    /// Hour-by-hour breakdown for a single day, used by the dashboard timeline.
    public func hourlyStatistics(for date: Date) -> [HourPattern] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.endOfDay(for: dayStart)
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: dayStart, end: dayEnd))) ?? []
        var seconds = [Double](repeating: 0, count: 24)
        var words = [Int](repeating: 0, count: 24)
        var counts = [Int](repeating: 0, count: 24)

        for session in sessions {
            let startHour = calendar.hour(of: max(session.startedAt, dayStart))
            if session.startedAt >= dayStart && session.startedAt < dayEnd {
                counts[startHour] += 1
            }
            var rangeSeconds: [Double] = [Double](repeating: 0, count: 24)
            var totalSeconds = 0.0
            let clampedRanges = session.activeRanges.isEmpty
                ? (session.activeSeconds > 0 ? [TimeRange(start: session.startedAt, end: min(session.startedAt.addingTimeInterval(session.activeSeconds), session.endedAt ?? dayEnd))] : [])
                : session.activeRanges
            for range in clampedRanges {
                var cursor = max(range.start, dayStart)
                let end = min(range.end, dayEnd)
                while cursor < end {
                    let hourStart = calendar.calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                    let hourEnd = calendar.calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end
                    let sliceEnd = min(hourEnd, end)
                    let slice = sliceEnd.timeIntervalSince(cursor)
                    let hour = calendar.hour(of: cursor)
                    seconds[hour] += slice
                    rangeSeconds[hour] += slice
                    totalSeconds += slice
                    cursor = sliceEnd
                }
            }
            let net = session.netWordChange ?? 0
            if totalSeconds > 0 {
                for hour in 0..<24 where rangeSeconds[hour] > 0 {
                    words[hour] += Int((Double(net) * rangeSeconds[hour] / totalSeconds).rounded())
                }
            } else if session.startedAt >= dayStart && session.startedAt < dayEnd {
                words[startHour] += net
            }
        }

        return (0..<24).map { hour in
            HourPattern(hour: hour, netWords: words[hour], activeSeconds: seconds[hour], sessions: counts[hour])
        }
    }

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

    // MARK: - Chart data

    public func sessionPoints(filter: SessionFilter = SessionFilter()) -> [SessionPoint] {
        let sessions = (try? sessionRepository.sessions(filter: filter)) ?? []
        let allSnapshots = (try? snapshotRepository.all()) ?? []
        let byDocument = Dictionary(grouping: allSnapshots.compactMap { snapshot -> (String, WordCountSnapshot)? in
            guard let id = snapshot.documentID else { return nil }
            return (id, snapshot)
        }, by: { $0.0 }).mapValues { $0.map(\.1).sorted { $0.timestamp < $1.timestamp } }

        return sessions.map { session in
            SessionPoint(
                id: session.id,
                date: session.startedAt,
                activeMinutes: session.activeSeconds / 60,
                netWords: session.netWordChange ?? 0,
                pace: pace(for: session, snapshotsByDocument: byDocument),
                sessionType: session.sessionType,
                applicationID: session.applicationID,
                projectID: session.projectID
            )
        }
    }

    /// Typing pace in words per minute, derived from growth in the document's
    /// character count (5 characters = 1 word). Deletions and modifier keys add
    /// nothing. This is derived from the app's character count, not per-key
    /// counting, and it includes pasted characters.
    public func typingPace(for session: Session) -> Double? {
        guard let documentID = session.documentID else { return nil }
        let snapshots = (try? snapshotRepository.snapshots(forDocument: documentID)) ?? []
        return computePace(session: session, snapshots: snapshots)
    }

    private func pace(for session: Session, snapshotsByDocument: [String: [WordCountSnapshot]]) -> Double? {
        guard let documentID = session.documentID else { return nil }
        return computePace(session: session, snapshots: snapshotsByDocument[documentID] ?? [])
    }

    private func computePace(session: Session, snapshots: [WordCountSnapshot]) -> Double? {
        guard session.activeSeconds > 0 else { return nil }
        let end = session.endedAt ?? dateProvider.now
        let inRange = snapshots.filter { $0.timestamp >= session.startedAt && $0.timestamp <= end }
        let characters = inRange.compactMap(\.characterCount)
        guard characters.count >= 2 else { return nil }
        var added = 0
        for index in 1..<characters.count {
            let delta = characters[index] - characters[index - 1]
            if delta > 0 { added += delta }
        }
        guard added > 0 else { return nil }
        return (Double(added) / 5.0) / (session.activeSeconds / 60.0)
    }

    public func hourWeekdayMatrix(from start: Date, to end: Date) -> [HourWeekdayCell] {
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: start, end: end))) ?? []
        var words = [Int](repeating: 0, count: 7 * 24)
        var seconds = [Double](repeating: 0, count: 7 * 24)
        for session in sessions {
            let weekday = max(0, min(6, calendar.weekday(of: session.startedAt) - 1))
            let net = session.netWordChange ?? 0
            var totalSeconds = 0.0
            var perHour = [Double](repeating: 0, count: 24)
            let ranges = session.activeRanges.isEmpty && session.activeSeconds > 0
                ? [TimeRange(start: session.startedAt, end: min(session.startedAt.addingTimeInterval(session.activeSeconds), session.endedAt ?? end))]
                : session.activeRanges
            for range in ranges {
                var cursor = max(range.start, start)
                let clampedEnd = min(range.end, end)
                while cursor < clampedEnd {
                    let hourStart = calendar.calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                    let hourEnd = calendar.calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? clampedEnd
                    let sliceEnd = min(hourEnd, clampedEnd)
                    let slice = sliceEnd.timeIntervalSince(cursor)
                    perHour[calendar.hour(of: cursor)] += slice
                    totalSeconds += slice
                    cursor = sliceEnd
                }
            }
            for hour in 0..<24 where perHour[hour] > 0 {
                seconds[weekday * 24 + hour] += perHour[hour]
                if totalSeconds > 0 {
                    words[weekday * 24 + hour] += Int((Double(net) * perHour[hour] / totalSeconds).rounded())
                }
            }
            if totalSeconds == 0 {
                words[weekday * 24 + calendar.hour(of: session.startedAt)] += net
            }
        }
        var cells: [HourWeekdayCell] = []
        for weekday in 1...7 {
            for hour in 0..<24 {
                let index = (weekday - 1) * 24 + hour
                cells.append(HourWeekdayCell(weekday: weekday, hour: hour, words: words[index], activeSeconds: seconds[index]))
            }
        }
        return cells
    }

    public func sessionTypeBreakdown(from start: Date, to end: Date) -> [SessionTypeDay] {
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: start, end: end))) ?? []
        var buckets: [String: (date: Date, type: SessionType, words: Int, seconds: Double)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            let key = "\(calendar.dayKey(for: day))-\(session.sessionType.rawValue)"
            var entry = buckets[key] ?? (day, session.sessionType, 0, 0)
            entry.words += session.netWordChange ?? 0
            entry.seconds += session.activeSeconds
            buckets[key] = entry
        }
        return buckets.values
            .map { SessionTypeDay(dayKey: calendar.dayKey(for: $0.date), date: $0.date, type: $0.type, words: $0.words, activeSeconds: $0.seconds) }
            .sorted { $0.date < $1.date }
    }

    public func dailyWordsByProject(from start: Date, to end: Date) -> [ProjectDayWords] {
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: start, end: end))) ?? []
        var buckets: [String: (date: Date, projectID: String?, words: Int)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            let key = "\(calendar.dayKey(for: day))-\(session.projectID ?? "none")"
            var entry = buckets[key] ?? (day, session.projectID, 0)
            entry.words += session.netWordChange ?? 0
            buckets[key] = entry
        }
        return buckets.values
            .map { ProjectDayWords(dayKey: calendar.dayKey(for: $0.date), date: $0.date, projectID: $0.projectID, words: $0.words) }
            .sorted { $0.date < $1.date }
    }

    public func addedRemovedSeries(from start: Date, to end: Date) -> [AddedRemovedPoint] {
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: start, end: end))) ?? []
        var buckets: [String: (date: Date, added: Int, removed: Int)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            let key = calendar.dayKey(for: day)
            var entry = buckets[key] ?? (day, 0, 0)
            if session.wordsAdded != nil || session.wordsRemoved != nil {
                entry.added += session.wordsAdded ?? 0
                entry.removed += session.wordsRemoved ?? 0
            } else if let net = session.netWordChange {
                if net >= 0 { entry.added += net } else { entry.removed += -net }
            }
            buckets[key] = entry
        }
        return buckets.values
            .map { AddedRemovedPoint(dayKey: calendar.dayKey(for: $0.date), date: $0.date, added: $0.added, removed: $0.removed) }
            .sorted { $0.date < $1.date }
    }

    public func paceHistory(from start: Date, to end: Date) -> [PacePoint] {
        let sessions = (try? sessionRepository.sessions(in: DateInterval(start: start, end: end))) ?? []
        let allSnapshots = (try? snapshotRepository.all()) ?? []
        let byDocument = Dictionary(grouping: allSnapshots.compactMap { snapshot -> (String, WordCountSnapshot)? in
            guard let id = snapshot.documentID else { return nil }
            return (id, snapshot)
        }, by: { $0.0 }).mapValues { $0.map(\.1).sorted { $0.timestamp < $1.timestamp } }
        return sessions.compactMap { session -> PacePoint? in
            guard let value = pace(for: session, snapshotsByDocument: byDocument), value > 0 else { return nil }
            return PacePoint(date: session.startedAt, pace: value)
        }.sorted { $0.date < $1.date }
    }

    public func weekdayMomentum(reference: Date) -> [WeekdayMomentum] {
        let thisStart = calendar.startOfWeek(for: reference)
        let lastStart = calendar.addingDays(-7, to: thisStart)
        func totals(_ start: Date) -> [Int] {
            (0..<7).map { offset in dailyStatistics(date: calendar.addingDays(offset, to: start)).netWords }
        }
        let this = totals(thisStart), last = totals(lastStart)
        return (0..<7).map { WeekdayMomentum(weekday: $0, thisWeek: this[$0], lastWeek: last[$0]) }
    }

    public func streakHistory() -> [StreakRun] {
        let threshold = settings.streakThresholdWords
        let aggregates = (try? aggregateRepository.all()) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.dayKey, $0) })
        let scheduled = settings.writingSchedule.filter(\.enabled).map(\.weekday)
        guard let firstDate = aggregates.map(\.date).min() else { return [] }
        let today = calendar.startOfDay(for: dateProvider.now)
        var runs: [StreakRun] = []
        var runStart: Date?
        var runEnd: Date?
        var length = 0
        for day in calendar.days(from: firstDate, through: today) {
            let weekday = calendar.weekday(of: day)
            if !scheduled.isEmpty && !scheduled.contains(weekday) { continue }
            let aggregate = byKey[calendar.dayKey(for: day)]
            let writes = aggregate.map { isWritingDay($0, threshold: threshold) } ?? false
            if writes {
                if runStart == nil { runStart = day }
                runEnd = day
                length += 1
            } else if calendar.startOfDay(for: day) == today {
                continue
            } else if let start = runStart, let end = runEnd {
                runs.append(StreakRun(start: start, end: end, length: length, isCurrent: false))
                runStart = nil; runEnd = nil; length = 0
            }
        }
        if let start = runStart, let end = runEnd {
            runs.append(StreakRun(start: start, end: end, length: length, isCurrent: true))
        }
        return runs
    }

    public func monthlyYearMatrix() -> [MonthlyYearCell] {
        let aggregates = (try? aggregateRepository.all()) ?? []
        var buckets: [String: (year: Int, month: Int, words: Int)] = [:]
        for aggregate in aggregates {
            let comps = calendar.calendar.dateComponents([.year, .month], from: aggregate.date)
            let year = comps.year ?? 0, month = comps.month ?? 0
            let key = "\(year)-\(month)"
            var entry = buckets[key] ?? (year, month, 0)
            entry.words += aggregate.netWords
            buckets[key] = entry
        }
        return buckets.values
            .map { MonthlyYearCell(year: $0.year, month: $0.month, words: $0.words) }
            .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    public func careerOutputByYearType() -> [YearTypeWords] {
        let projects = (try? projectRepository.all()) ?? []
        var typeByProject: [String: ProjectType] = [:]
        for project in projects { typeByProject[project.id] = project.type }
        let sessions = (try? sessionRepository.completed()) ?? []
        var buckets: [String: Int] = [:]
        for session in sessions {
            let year = calendar.yearKey(for: session.startedAt)
            let type = session.projectID.flatMap { typeByProject[$0] } ?? .other
            buckets["\(year)-\(type.rawValue)", default: 0] += session.netWordChange ?? 0
        }
        return buckets.map { key, words in
            let parts = key.split(separator: "-")
            let year = String(parts.first ?? "")
            let type = ProjectType(rawValue: String(parts.dropFirst().joined(separator: "-"))) ?? .other
            return YearTypeWords(year: year, type: type, words: words)
        }.sorted { $0.year < $1.year }
    }

    public func cumulativeProjectSeries(projectID: String) -> [CumulativePoint] {
        guard let project = try? projectRepository.find(id: projectID) else { return [] }
        let sessions = ((try? sessionRepository.sessions(forProject: projectID)) ?? [])
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        var running = project.startingWordCount
        var points = [CumulativePoint(date: project.createdAt, words: running)]
        for session in sessions {
            if let ending = session.endingWordCount {
                running = ending
            } else {
                running += session.netWordChange ?? 0
            }
            points.append(CumulativePoint(date: session.endedAt ?? session.startedAt, words: running))
        }
        return points
    }

    public func documentWordCountSeries(projectID: String) -> [DocumentWordSeries] {
        let snapshots = ((try? snapshotRepository.snapshots(forProject: projectID)) ?? [])
            .filter { $0.documentID != nil }
            .sorted { $0.timestamp < $1.timestamp }
        let grouped = Dictionary(grouping: snapshots, by: { $0.documentID! })
        let documents = (try? DocumentRepository(database: database).documents(forProject: projectID)) ?? []
        let names = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.displayName) })
        return grouped.map { documentID, snaps in
            DocumentWordSeries(
                documentID: documentID,
                displayName: names[documentID] ?? "Document",
                points: snaps.map { CumulativePoint(date: $0.timestamp, words: $0.wordCount) }
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    public func deadlinePaceSeries(projectID: String) -> [CumulativePoint] {
        guard let project = try? projectRepository.find(id: projectID),
              let target = project.targetWordCount,
              let deadline = project.deadline else { return [] }
        let start = project.startedAt ?? project.createdAt
        guard deadline > start else { return [] }
        return [
            CumulativePoint(date: start, words: project.startingWordCount),
            CumulativePoint(date: deadline, words: target)
        ]
    }

    /// Simple moving average; positions with fewer than `window` samples are nil.
    public static func movingAverage(_ values: [Double], window: Int) -> [Double?] {
        guard window > 0 else { return values.map { $0 } }
        var result: [Double?] = []
        var sum = 0.0
        for index in values.indices {
            sum += values[index]
            if index >= window { sum -= values[index - window] }
            result.append(index >= window - 1 ? sum / Double(window) : nil)
        }
        return result
    }
}
