import Foundation

public struct WritingReport: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    public var subtitle: String
    public var period: PeriodStatistics
    public var highlights: [String]
    public var generatedAt: Date
}

public enum AchievementUnit: String, Codable, Sendable {
    case words
    case days
    case sessions
    case projects

    public var displayName: String {
        switch self {
        case .words: return "words"
        case .days: return "days"
        case .sessions: return "sessions"
        case .projects: return "projects"
        }
    }
}

public struct Achievement: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let isUnlocked: Bool
    public let currentValue: Double
    public let threshold: Double
    public let unit: AchievementUnit
    public let symbol: String

    public var progress: Double {
        threshold > 0 ? min(1, max(0, currentValue / threshold)) : 0
    }

    /// Grouped current value, e.g. "34,735".
    public var currentText: String { Self.format(currentValue) }
    /// Grouped target value, e.g. "1,000,000".
    public var targetText: String { Self.format(threshold) }
    /// Numeric progress, e.g. "34,735 / 1,000,000 words".
    public var progressText: String { "\(currentText) / \(targetText) \(unit.displayName)" }
    /// Remaining amount, when the achievement is not yet unlocked.
    public var remainingText: String? {
        guard !isUnlocked, threshold > currentValue else { return nil }
        return "\(Self.format(threshold - currentValue)) \(unit.displayName) to go"
    }

    private static func format(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}

public struct StatComparison: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let current: Double
    public let previous: Double
    public let isPercentage: Bool

    public var delta: Double { current - previous }
    public var percentageChange: Double? {
        guard previous != 0 else { return nil }
        return (current - previous) / abs(previous) * 100
    }
}

public final class ReportService {
    private let statistics: StatisticsService
    private let dateProvider: DateProviding
    private let calendar: CalendarContext

    public init(statistics: StatisticsService, dateProvider: DateProviding = SystemDateProvider(), calendarContext: CalendarContext? = nil) {
        self.statistics = statistics
        self.dateProvider = dateProvider
        self.calendar = calendarContext ?? statistics.calendar
    }

    public func weeklyReport(containing date: Date) -> WritingReport {
        let period = statistics.weeklyStatistics(containing: date)
        return makeReport(title: "Weekly Report", subtitle: dateRangeString(period), period: period)
    }

    public func monthlyReport(containing date: Date) -> WritingReport {
        let period = statistics.monthlyStatistics(containing: date)
        return makeReport(title: "Monthly Report", subtitle: dateRangeString(period), period: period)
    }

    public func yearlyReport(year: Int) -> WritingReport {
        let period = statistics.yearlyStatistics(year: year)
        return makeReport(title: "Yearly Report", subtitle: "\(year)", period: period)
    }

    public func yearInReview(year: Int) -> WritingReport {
        let period = statistics.yearlyStatistics(year: year)
        var highlights: [String] = []
        highlights.append("\(period.netWords.formatted()) words")
        highlights.append("\(DurationFormatter.short(period.activeSeconds)) active")
        highlights.append("\(period.sessions) sessions")
        highlights.append("\(period.writingDays) writing days")
        if let best = period.bestDay {
            highlights.append("Best day: \(best.words.formatted()) words")
        }
        highlights.append("Longest streak: \(period.longestStreak) days")
        let lifetime = statistics.lifetimeStatistics()
        if let productiveMonth = lifetime.mostProductiveMonth {
            highlights.append("Most productive month: \(productiveMonth)")
        }
        return WritingReport(
            title: "Your \(year) Writing Year",
            subtitle: "\(year)",
            period: period,
            highlights: highlights,
            generatedAt: dateProvider.now
        )
    }

    // MARK: - Comparisons

    public func yearOverYearComparison() -> StatComparison {
        let currentYear = calendar.calendar.component(.year, from: dateProvider.now)
        let current = statistics.yearlyStatistics(year: currentYear).netWords
        let previous = statistics.yearlyStatistics(year: currentYear - 1).netWords
        return StatComparison(label: "Words vs. last year", current: Double(current), previous: Double(previous), isPercentage: false)
    }

    public func monthOverMonthComparison() -> StatComparison {
        let now = dateProvider.now
        let current = statistics.monthlyStatistics(containing: now).netWords
        let previousDate = calendar.calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = statistics.monthlyStatistics(containing: previousDate).netWords
        return StatComparison(label: "Words vs. last month", current: Double(current), previous: Double(previous), isPercentage: false)
    }

    public func projectComparison(_ first: Project, _ second: Project) throws -> [StatComparison] {
        let a = try statistics.projectStatistics(projectID: first.id)
        let b = try statistics.projectStatistics(projectID: second.id)
        return [
            StatComparison(label: "Net words", current: Double(a.netWords), previous: Double(b.netWords), isPercentage: false),
            StatComparison(label: "Active time", current: a.totalActiveSeconds, previous: b.totalActiveSeconds, isPercentage: false),
            StatComparison(label: "Sessions", current: Double(a.sessionCount), previous: Double(b.sessionCount), isPercentage: false),
            StatComparison(label: "Avg words/day", current: a.averageWordsPerDay, previous: b.averageWordsPerDay, isPercentage: false),
            StatComparison(label: "Avg words/session", current: a.averageWordsPerSession, previous: b.averageWordsPerSession, isPercentage: false)
        ]
    }

    // MARK: - Achievements

    public func achievements() -> [Achievement] {
        let lifetime = statistics.lifetimeStatistics()
        func achievement(id: String, title: String, detail: String, value: Double, threshold: Double, unit: AchievementUnit, symbol: String) -> Achievement {
            Achievement(
                id: id, title: title, detail: detail,
                isUnlocked: value >= threshold,
                currentValue: value,
                threshold: threshold,
                unit: unit,
                symbol: symbol
            )
        }
        return [
            achievement(id: "first1k", title: "First 1,000 words", detail: "Write your first thousand words",
                        value: Double(lifetime.lifetimeNetWords), threshold: 1_000, unit: .words, symbol: "text.book.closed"),
            achievement(id: "10k", title: "10,000 words", detail: "Reach 10,000 lifetime words",
                        value: Double(lifetime.lifetimeNetWords), threshold: 10_000, unit: .words, symbol: "books.vertical"),
            achievement(id: "100k", title: "100,000 words", detail: "Reach 100,000 lifetime words",
                        value: Double(lifetime.lifetimeNetWords), threshold: 100_000, unit: .words, symbol: "book"),
            achievement(id: "1m", title: "One million words", detail: "Reach one million lifetime words",
                        value: Double(lifetime.lifetimeNetWords), threshold: 1_000_000, unit: .words, symbol: "star"),
            achievement(id: "days100", title: "100 writing days", detail: "Write on 100 days",
                        value: Double(lifetime.writingDays), threshold: 100, unit: .days, symbol: "calendar"),
            achievement(id: "sessions100", title: "100 sessions", detail: "Complete 100 writing sessions",
                        value: Double(lifetime.totalSessions), threshold: 100, unit: .sessions, symbol: "clock"),
            achievement(id: "streak30", title: "30-day streak", detail: "Write for 30 consecutive days",
                        value: Double(lifetime.longestStreak), threshold: 30, unit: .days, symbol: "flame"),
            achievement(id: "project1", title: "First completed project", detail: "Mark a project complete",
                        value: Double(lifetime.completedProjects), threshold: 1, unit: .projects, symbol: "checkmark.seal")
        ]
    }

    // MARK: - Helpers

    private func makeReport(title: String, subtitle: String, period: PeriodStatistics) -> WritingReport {
        var highlights: [String] = []
        highlights.append("Words: \(period.netWords.formatted())")
        highlights.append("Time: \(DurationFormatter.short(period.activeSeconds))")
        highlights.append("Sessions: \(period.sessions)")
        highlights.append("Writing days: \(period.writingDays)/\(max(period.scheduledDays, calendar.daysBetween(period.startDate, period.endDate)))")
        highlights.append("Average/day: \(Int(period.averageWordsPerDay.rounded()).formatted())")
        if let best = period.bestDay {
            highlights.append("Best day: \(best.words.formatted())")
        }
        return WritingReport(title: title, subtitle: subtitle, period: period, highlights: highlights, generatedAt: dateProvider.now)
    }

    private func dateRangeString(_ period: PeriodStatistics) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let end = calendar.addingDays(-1, to: period.endDate)
        return "\(formatter.string(from: period.startDate)) – \(formatter.string(from: end))"
    }
}
