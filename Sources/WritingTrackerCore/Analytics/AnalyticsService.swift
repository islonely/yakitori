import Foundation

/// Analytics calculator for the additional visualizations.
///
/// It reuses the application's existing definitions (net word change, active
/// seconds, daily aggregates, streak/goal helpers) rather than re-deriving them,
/// and produces plain value models that the SwiftUI layer renders. Nothing here
/// inspects keystrokes; gross-worked figures are explicitly derived from the
/// existing added/removed aggregation and labelled as estimated.
public final class AnalyticsService {
    /// Bins/categories with fewer observations than this are not treated as
    /// meaningful.
    public static let minimumSampleSize = 3

    private let database: Database
    private let statistics: StatisticsService
    private let dateProvider: DateProviding
    private let sessionRepository: SessionRepository
    private let aggregateRepository: DailyAggregateRepository
    private let projectRepository: ProjectRepository
    private let goalRepository: GoalRepository

    public init(
        database: Database,
        statistics: StatisticsService,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.database = database
        self.statistics = statistics
        self.dateProvider = dateProvider
        self.sessionRepository = SessionRepository(database: database)
        self.aggregateRepository = DailyAggregateRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.goalRepository = GoalRepository(database: database)
    }

    private var calendar: CalendarContext { statistics.calendar }

    // MARK: - 1. Session duration distribution

    public func sessionDurationDistribution(filter: SessionFilter = SessionFilter()) -> SessionDurationDistribution {
        let durations = completedSessions(filter: filter).compactMap { session -> Double? in
            let seconds = session.duration
            guard seconds > 0 else { return nil }
            return seconds / 60.0
        }
        guard !durations.isEmpty else {
            return SessionDurationDistribution(bins: [], summary: .empty, sessionCount: 0)
        }
        let bins = histogram(
            values: durations,
            preferredBinCount: min(15, max(6, Int(Double(durations.count).squareRoot()) + 4)),
            label: { Self.minuteRangeLabel($0, $1) }
        )
        return SessionDurationDistribution(bins: bins, summary: StatisticsMath.summary(durations), sessionCount: durations.count)
    }

    // MARK: - 2. Daily output distribution

    public func dailyOutputDistribution(
        range: DateInterval,
        metric: DailyOutputMetric = .netWords
    ) -> DailyOutputDistribution {
        let days = statistics.dailyStatistics(from: range.start, to: calendar.addingDays(-1, to: range.end))
        let writingDays = days.filter { $0.sessionCount > 0 }
        let values = writingDays.map { day -> Double in
            switch metric {
            case .netWords: return Double(day.netWords)
            case .grossWorked: return Double(day.wordsAdded + day.wordsRemoved)
            }
        }
        guard !values.isEmpty else {
            return DailyOutputDistribution(metric: metric, bins: [], summary: .empty, writingDayCount: 0)
        }
        let bins = histogram(values: values, preferredBinCount: 12, label: { Self.wordRangeLabel($0, $1) })
        return DailyOutputDistribution(
            metric: metric,
            bins: bins,
            summary: StatisticsMath.summary(values),
            writingDayCount: values.count
        )
    }

    // MARK: - 3. Productivity by session length

    public func productivityBySessionLength(
        filter: SessionFilter = SessionFilter(),
        minimumSampleSize: Int = AnalyticsService.minimumSampleSize
    ) -> SessionLengthProductivity {
        let sessions = completedSessions(filter: filter)
        let buckets: [(label: String, lower: Double, upper: Double?)] = [
            ("<15 min", 0, 15),
            ("15-30 min", 15, 30),
            ("30-60 min", 30, 60),
            ("60-90 min", 60, 90),
            ("90-120 min", 90, 120),
            ("120-180 min", 120, 180),
            ("180+ min", 180, nil)
        ]
        var grouped: [[Double]] = Array(repeating: [], count: buckets.count)
        for session in sessions {
            guard session.activeSeconds > 0, let net = session.netWordChange else { continue }
            let minutes = session.duration / 60.0
            guard minutes > 0 else { continue }
            let index = buckets.firstIndex { bucket in
                let aboveLower = minutes >= bucket.lower
                let belowUpper = bucket.upper.map { minutes < $0 } ?? true
                return aboveLower && belowUpper
            }
            guard let index else { continue }
            grouped[index].append(Double(net) / (session.activeSeconds / 3600.0))
        }

        let bins = buckets.enumerated().map { index, bucket -> SessionLengthProductivityBin in
            let values = grouped[index]
            let sufficient = values.count >= minimumSampleSize
            let median = sufficient ? StatisticsMath.median(values) : 0
            return SessionLengthProductivityBin(
                label: bucket.label,
                lowerMinutes: bucket.lower,
                upperMinutes: bucket.upper,
                medianWordsPerHour: median,
                p25WordsPerHour: sufficient ? StatisticsMath.percentile(values, 0.25) : 0,
                p75WordsPerHour: sufficient ? StatisticsMath.percentile(values, 0.75) : 0,
                sampleCount: values.count,
                isSufficient: sufficient
            )
        }
        return SessionLengthProductivity(bins: bins, minimumSampleSize: minimumSampleSize)
    }

    // MARK: - 4. Goal performance history

    /// A single representative goal per period type is used so the trend is
    /// unambiguous; if several goals share a period type, the most recently
    /// created enabled goal wins.
    public func goalPerformance(period: GoalPeriod) -> GoalPerformanceHistory {
        let goals = ((try? goalRepository.enabled()) ?? [])
            .filter { $0.period == period }
            .sorted { $0.createdAt < $1.createdAt }
        guard let goal = goals.last else {
            return emptyGoalHistory(period: period, metric: .words)
        }

        let now = dateProvider.now
        let firstTracked = statistics.lifetimeStatistics().firstTrackedDay
        let effectiveStart = max(goal.startDate, firstTracked ?? goal.startDate)
        let currentStart = startOfCurrentPeriod(period: period, now: now)

        // Precompute daily stats once so long histories do not hammer the database.
        let spanStart = floorToPeriod(period: period, date: effectiveStart)
        let dayMap = dailyMap(from: spanStart, to: now)

        var results: [GoalPeriodResult] = []
        var cursor = spanStart
        var safety = 0
        while cursor < currentStart, safety < 3000 {
            safety += 1
            let end = endOfPeriod(period: period, start: cursor)
            guard end <= currentStart else { break }
            if let limit = goal.endDate, cursor >= limit { break }
            let value = periodValue(metric: goal.metric, start: cursor, end: end, dayMap: dayMap)
            results.append(
                GoalPeriodResult(
                    id: "\(goal.id)-\(cursor.timeIntervalSince1970)",
                    goalID: goal.id,
                    label: periodLabel(period: period, start: cursor),
                    start: cursor,
                    end: end,
                    metric: goal.metric,
                    target: goal.target,
                    actual: value
                )
            )
            cursor = end
        }

        guard !results.isEmpty else { return emptyGoalHistory(period: period, metric: goal.metric) }

        let attainments = results.map(\.attainment)
        let met = results.filter { $0.attainment >= 100 }.count
        let missed = results.count - met
        let successRate = results.isEmpty ? 0 : Double(met) / Double(results.count)
        var longestRun = 0
        var currentRun = 0
        for result in results {
            if result.attainment >= 100 {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }

        return GoalPerformanceHistory(
            period: period,
            metric: goal.metric,
            results: results,
            met: met,
            missed: missed,
            successRate: successRate,
            medianAttainment: StatisticsMath.median(attainments),
            averageAttainment: StatisticsMath.mean(attainments),
            longestSuccessRun: longestRun
        )
    }

    // MARK: - 5. Project velocity

    public func projectVelocity(
        projectID: String,
        granularity: VelocityGranularity = .weekly,
        range: DateInterval? = nil
    ) -> ProjectVelocity {
        var sessions = ((try? sessionRepository.sessions(forProject: projectID)) ?? [])
            .filter { $0.endedAt != nil }
        if let range {
            sessions = sessions.filter { $0.startedAt >= range.start && $0.startedAt < range.end }
        }
        guard !sessions.isEmpty else {
            return ProjectVelocity(projectID: projectID, granularity: granularity, points: [])
        }

        var totals: [Date: Int] = [:]
        for session in sessions {
            let bucket = granularity == .daily
                ? calendar.startOfDay(for: session.startedAt)
                : calendar.startOfWeek(for: session.startedAt)
            totals[bucket, default: 0] += session.netWordChange ?? 0
        }

        let sortedKeys = totals.keys.sorted()
        guard let first = sortedKeys.first, let last = sortedKeys.last else {
            return ProjectVelocity(projectID: projectID, granularity: granularity, points: [])
        }

        // Fill gaps so the line is continuous between first and last activity.
        var orderedKeys: [Date] = []
        var cursor = first
        var safety = 0
        while cursor <= last, safety < 5000 {
            safety += 1
            orderedKeys.append(cursor)
            cursor = granularity == .daily ? calendar.addingDays(1, to: cursor) : calendar.addingDays(7, to: cursor)
        }

        let window = granularity.rollingWindow
        var points: [VelocityPoint] = []
        for (index, key) in orderedKeys.enumerated() {
            let words = totals[key] ?? 0
            var rolling: Double?
            if index >= window - 1 {
                let slice = orderedKeys[(index - window + 1)...index].map { Double(totals[$0] ?? 0) }
                rolling = StatisticsMath.mean(slice)
            }
            points.append(VelocityPoint(date: key, words: words, rollingAverage: rolling))
        }
        return ProjectVelocity(projectID: projectID, granularity: granularity, points: points)
    }

    // MARK: - 6. Writing cadence

    public func writingCadence(filter: SessionFilter = SessionFilter()) -> WritingCadence {
        let sessions = completedSessions(filter: filter).sorted { $0.startedAt < $1.startedAt }
        guard sessions.count >= 2 else {
            return WritingCadence(bins: [], summary: .empty, gapCount: 0)
        }
        var gaps: [Double] = []
        for index in 1..<sessions.count {
            let previousEnd = sessions[index - 1].endedAt ?? sessions[index - 1].startedAt
            let gapSeconds = sessions[index].startedAt.timeIntervalSince(previousEnd)
            // Overlapping sessions are a data anomaly; ignore rather than treat
            // them as a zero-length gap.
            if gapSeconds >= 0 {
                gaps.append(gapSeconds / 60.0)
            }
        }
        let edges: [Double] = [0, 15, 30, 60, 120, 240, 480, 1440, 2880, 10080, 1_000_000_000]
        let labels = [
            "<15 min", "15-30 min", "30-60 min", "1-2 h", "2-4 h",
            "4-8 h", "8-24 h", "1-2 days", "2-7 days", "7+ days"
        ]
        let counts = StatisticsMath.binCounts(gaps, edges: edges)
        let bins = counts.enumerated().map { index, count in
            HistogramBin(
                label: labels[index],
                lowerBound: edges[index],
                upperBound: edges[index + 1],
                count: count
            )
        }
        return WritingCadence(bins: bins, summary: StatisticsMath.summary(gaps), gapCount: gaps.count)
    }

    // MARK: - 7. Project effort by phase

    public func effortByPhase(projectIDs: [String], range: DateInterval? = nil) -> [ProjectPhaseEffort] {
        let projects = (try? projectRepository.all()) ?? []
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return projectIDs.compactMap { projectID in
            var sessions = ((try? sessionRepository.sessions(forProject: projectID)) ?? [])
                .filter { $0.endedAt != nil }
            if let range {
                sessions = sessions.filter { $0.startedAt >= range.start && $0.startedAt < range.end }
            }
            var totals: [SessionType: Double] = [:]
            for session in sessions {
                totals[session.sessionType, default: 0] += session.activeSeconds
            }
            let total = totals.values.reduce(0, +)
            guard total > 0 else { return nil }
            let slices = SessionType.allCases.compactMap { type -> PhaseEffortSlice? in
                let seconds = totals[type] ?? 0
                guard seconds > 0 else { return nil }
                return PhaseEffortSlice(type: type, activeSeconds: seconds, fraction: seconds / total)
            }
            return ProjectPhaseEffort(
                projectID: projectID,
                projectName: names[projectID] ?? "Project",
                slices: slices,
                totalActiveSeconds: total
            )
        }
    }

    // MARK: - 8. Cumulative lifetime output

    public func cumulativeLifetimeOutput(metric: CumulativeOutputMetric = .netWords) -> [CumulativeOutputPoint] {
        let aggregates = (try? aggregateRepository.all()) ?? []
        var running = 0
        return aggregates.map { aggregate in
            switch metric {
            case .netWords:
                running += aggregate.netWords
            case .grossWorked:
                running += aggregate.wordsAdded + aggregate.wordsRemoved
            }
            return CumulativeOutputPoint(date: aggregate.date, value: running)
        }
    }

    // MARK: - 9. Productivity variability

    /// Variability is measured over **writing days** (days with at least one
    /// session), using a rolling window. The coefficient of variation is nil when
    /// the window mean is zero.
    public func outputVariability(window: Int = 7, range: DateInterval) -> OutputVariability {
        guard window > 1 else {
            return OutputVariability(window: window, points: [], usesWritingDaysOnly: true)
        }
        let days = statistics.dailyStatistics(from: range.start, to: calendar.addingDays(-1, to: range.end))
        let writing = days
            .filter { $0.sessionCount > 0 }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, value: Double($0.netWords)) }
        guard writing.count >= window else {
            return OutputVariability(window: window, points: [], usesWritingDaysOnly: true)
        }
        var points: [VariabilityPoint] = []
        for index in (window - 1)..<writing.count {
            let slice = writing[(index - window + 1)...index].map(\.value)
            let mean = StatisticsMath.mean(slice)
            let deviation = StatisticsMath.standardDeviation(slice)
            let cv = mean != 0 ? deviation / abs(mean) : nil
            points.append(
                VariabilityPoint(
                    date: writing[index].date,
                    observationCount: window,
                    mean: mean,
                    standardDeviation: deviation,
                    coefficientOfVariation: cv
                )
            )
        }
        return OutputVariability(window: window, points: points, usesWritingDaysOnly: true)
    }

    // MARK: - 10. Productivity by work type

    public func productivityByWorkType(
        filter: SessionFilter = SessionFilter(),
        minimumSampleSize: Int = AnalyticsService.minimumSampleSize
    ) -> [WorkTypeProductivity] {
        let sessions = completedSessions(filter: filter)
        var grouped: [SessionType: [Double]] = [:]
        for session in sessions {
            guard session.activeSeconds > 0, let net = session.netWordChange else { continue }
            grouped[session.sessionType, default: []].append(Double(net) / (session.activeSeconds / 3600.0))
        }
        return SessionType.allCases.map { type in
            let values = grouped[type] ?? []
            let sufficient = values.count >= minimumSampleSize
            return WorkTypeProductivity(
                type: type,
                medianWordsPerHour: sufficient ? StatisticsMath.median(values) : nil,
                meanWordsPerHour: sufficient ? StatisticsMath.mean(values) : nil,
                p25WordsPerHour: sufficient ? StatisticsMath.percentile(values, 0.25) : nil,
                p75WordsPerHour: sufficient ? StatisticsMath.percentile(values, 0.75) : nil,
                sampleCount: values.count,
                isSufficient: sufficient
            )
        }
    }

    // MARK: - Shared helpers

    private func completedSessions(filter: SessionFilter) -> [Session] {
        ((try? sessionRepository.sessions(filter: filter)) ?? []).filter { $0.endedAt != nil }
    }

    private func histogram(
        values: [Double],
        preferredBinCount: Int,
        label: (Double, Double) -> String
    ) -> [HistogramBin] {
        guard let minimum = values.min(), let maximum = values.max() else { return [] }
        let edges: [Double]
        if maximum <= minimum {
            // All observations identical: a single bin is the honest representation.
            edges = [minimum, minimum + 1]
        } else {
            edges = StatisticsMath.equalWidthEdges(values, binCount: preferredBinCount) ?? [minimum, maximum]
        }
        let counts = StatisticsMath.binCounts(values, edges: edges)
        return counts.enumerated().map { index, count in
            HistogramBin(
                label: label(edges[index], edges[index + 1]),
                lowerBound: edges[index],
                upperBound: edges[index + 1],
                count: count
            )
        }
    }

    private static func minuteRangeLabel(_ lower: Double, _ upper: Double) -> String {
        "\(Int(lower.rounded()))-\(Int(upper.rounded())) min"
    }

    private static func wordRangeLabel(_ lower: Double, _ upper: Double) -> String {
        "\(Int(lower.rounded())) to \(Int(upper.rounded()))"
    }

    // MARK: - Goal period helpers

    private func emptyGoalHistory(period: GoalPeriod, metric: GoalMetric) -> GoalPerformanceHistory {
        GoalPerformanceHistory(
            period: period, metric: metric, results: [], met: 0, missed: 0,
            successRate: 0, medianAttainment: 0, averageAttainment: 0, longestSuccessRun: 0
        )
    }

    private func floorToPeriod(period: GoalPeriod, date: Date) -> Date {
        switch period {
        case .daily: return calendar.startOfDay(for: date)
        case .weekly: return calendar.startOfWeek(for: date)
        case .monthly: return calendar.startOfMonth(for: date)
        case .project, .deadline: return calendar.startOfDay(for: date)
        }
    }

    private func startOfCurrentPeriod(period: GoalPeriod, now: Date) -> Date {
        switch period {
        case .daily: return calendar.startOfDay(for: now)
        case .weekly: return calendar.startOfWeek(for: now)
        case .monthly: return calendar.startOfMonth(for: now)
        case .project, .deadline: return now
        }
    }

    private func endOfPeriod(period: GoalPeriod, start: Date) -> Date {
        switch period {
        case .daily: return calendar.addingDays(1, to: start)
        case .weekly: return calendar.addingDays(7, to: start)
        case .monthly: return calendar.calendar.date(byAdding: .month, value: 1, to: start) ?? calendar.addingDays(31, to: start)
        case .project, .deadline: return start
        }
    }

    private func dailyMap(from start: Date, to end: Date) -> [String: DailyStatistics] {
        let days = statistics.dailyStatistics(from: start, to: end)
        return Dictionary(uniqueKeysWithValues: days.map { ($0.dayKey, $0) })
    }

    private func periodValue(metric: GoalMetric, start: Date, end: Date, dayMap: [String: DailyStatistics]) -> Double {
        var words = 0
        var activeSeconds = 0.0
        var sessions = 0
        for day in calendar.days(from: start, through: calendar.addingDays(-1, to: end)) {
            guard let stat = dayMap[calendar.dayKey(for: day)] else { continue }
            words += stat.netWords
            activeSeconds += stat.activeSeconds
            sessions += stat.sessionCount
        }
        switch metric {
        case .words: return Double(words)
        case .activeMinutes: return activeSeconds / 60
        case .sessions: return Double(sessions)
        }
    }

    private func periodLabel(period: GoalPeriod, start: Date) -> String {
        switch period {
        case .daily: return formatDate(start, "MMM d")
        case .weekly: return "Week of " + formatDate(start, "MMM d")
        case .monthly: return formatDate(start, "MMMM yyyy")
        case .project, .deadline: return formatDate(start, "MMM d, yyyy")
        }
    }

    private func formatDate(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
