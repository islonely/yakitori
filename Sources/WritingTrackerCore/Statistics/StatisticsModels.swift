import Foundation

public struct DailyStatistics: Codable, Hashable, Sendable {
    public var date: Date
    public var dayKey: String
    public var wordsAdded: Int
    public var wordsRemoved: Int
    public var netWords: Int
    public var activeSeconds: Double
    public var focusSeconds: Double
    public var sessionCount: Int
    public var projectCount: Int
    public var firstSessionAt: Date?
    public var lastSessionAt: Date?

    public var isWritingDay: Bool { sessionCount > 0 && (netWords != 0 || activeSeconds > 0) }

    public var averageSessionSeconds: Double {
        sessionCount > 0 ? activeSeconds / Double(sessionCount) : 0
    }

    public var wordsPerMinute: Double? {
        guard activeSeconds > 0, netWords != 0 else { return nil }
        return Double(netWords) / (activeSeconds / 60)
    }

    public init(aggregate: DailyAggregate) {
        self.date = aggregate.date
        self.dayKey = aggregate.dayKey
        self.wordsAdded = aggregate.wordsAdded
        self.wordsRemoved = aggregate.wordsRemoved
        self.netWords = aggregate.netWords
        self.activeSeconds = aggregate.activeSeconds
        self.focusSeconds = aggregate.focusSeconds
        self.sessionCount = aggregate.sessionCount
        self.projectCount = aggregate.projectCount
        self.firstSessionAt = aggregate.firstSessionAt
        self.lastSessionAt = aggregate.lastSessionAt
    }
}

public struct BestDay: Codable, Hashable, Sendable {
    public var date: Date
    public var words: Int
}

public struct PeriodStatistics: Codable, Hashable, Sendable {
    public var startDate: Date
    public var endDate: Date
    public var netWords: Int
    public var wordsAdded: Int
    public var wordsRemoved: Int
    public var activeSeconds: Double
    public var focusSeconds: Double
    public var sessions: Int
    public var writingDays: Int
    public var scheduledDays: Int
    public var averageWordsPerDay: Double
    public var averageWordsPerSession: Double
    public var bestDay: BestDay?
    public var currentStreak: Int
    public var longestStreak: Int
    public var goalCompletion: Double?

    public init(
        startDate: Date,
        endDate: Date,
        netWords: Int = 0,
        wordsAdded: Int = 0,
        wordsRemoved: Int = 0,
        activeSeconds: Double = 0,
        focusSeconds: Double = 0,
        sessions: Int = 0,
        writingDays: Int = 0,
        scheduledDays: Int = 0,
        averageWordsPerDay: Double = 0,
        averageWordsPerSession: Double = 0,
        bestDay: BestDay? = nil,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        goalCompletion: Double? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.netWords = netWords
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
        self.activeSeconds = activeSeconds
        self.focusSeconds = focusSeconds
        self.sessions = sessions
        self.writingDays = writingDays
        self.scheduledDays = scheduledDays
        self.averageWordsPerDay = averageWordsPerDay
        self.averageWordsPerSession = averageWordsPerSession
        self.bestDay = bestDay
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.goalCompletion = goalCompletion
    }
}

public struct LifetimeStatistics: Codable, Hashable, Sendable {
    public var lifetimeNetWords: Int
    public var wordsAdded: Int
    public var wordsRemoved: Int
    public var writingDays: Int
    public var totalActiveSeconds: Double
    public var totalFocusSeconds: Double
    public var totalSessions: Int
    public var projectCount: Int
    public var completedProjects: Int
    public var bestDay: BestDay?
    public var bestSessionWords: Int?
    public var bestSessionID: String?
    public var bestWordsPerMinute: Double?
    public var bestWordsPerHour: Double?
    public var longestStreak: Int
    public var currentStreak: Int
    public var averageWordsPerDay: Double
    public var averageWordsPerSession: Double
    public var firstTrackedDay: Date?
    public var mostProductiveYear: String?
    public var mostProductiveMonth: String?
    public var longestSessionSeconds: Double

    public init(
        lifetimeNetWords: Int = 0,
        wordsAdded: Int = 0,
        wordsRemoved: Int = 0,
        writingDays: Int = 0,
        totalActiveSeconds: Double = 0,
        totalFocusSeconds: Double = 0,
        totalSessions: Int = 0,
        projectCount: Int = 0,
        completedProjects: Int = 0,
        bestDay: BestDay? = nil,
        bestSessionWords: Int? = nil,
        bestSessionID: String? = nil,
        bestWordsPerMinute: Double? = nil,
        bestWordsPerHour: Double? = nil,
        longestStreak: Int = 0,
        currentStreak: Int = 0,
        averageWordsPerDay: Double = 0,
        averageWordsPerSession: Double = 0,
        firstTrackedDay: Date? = nil,
        mostProductiveYear: String? = nil,
        mostProductiveMonth: String? = nil,
        longestSessionSeconds: Double = 0
    ) {
        self.lifetimeNetWords = lifetimeNetWords
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
        self.writingDays = writingDays
        self.totalActiveSeconds = totalActiveSeconds
        self.totalFocusSeconds = totalFocusSeconds
        self.totalSessions = totalSessions
        self.projectCount = projectCount
        self.completedProjects = completedProjects
        self.bestDay = bestDay
        self.bestSessionWords = bestSessionWords
        self.bestSessionID = bestSessionID
        self.bestWordsPerMinute = bestWordsPerMinute
        self.bestWordsPerHour = bestWordsPerHour
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.averageWordsPerDay = averageWordsPerDay
        self.averageWordsPerSession = averageWordsPerSession
        self.firstTrackedDay = firstTrackedDay
        self.mostProductiveYear = mostProductiveYear
        self.mostProductiveMonth = mostProductiveMonth
        self.longestSessionSeconds = longestSessionSeconds
    }
}

public struct StreakStatistics: Codable, Hashable, Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var thresholdWords: Int
    public var lastWritingDay: Date?
    public var scheduledWeekdays: [Int]
}

public struct HourPattern: Codable, Hashable, Sendable {
    public var hour: Int
    public var netWords: Int
    public var activeSeconds: Double
    public var sessions: Int
}

public struct WeekdayPattern: Codable, Hashable, Sendable {
    public var weekday: Int
    public var netWords: Int
    public var activeSeconds: Double
    public var sessions: Int
    public var averageWords: Double
}

public struct ProductivityPatterns: Codable, Hashable, Sendable {
    public var byHour: [HourPattern]
    public var byWeekday: [WeekdayPattern]
    public var bestHour: Int?
    public var bestWeekday: Int?
    public var averageSessionSeconds: Double
    public var averageSessionWords: Double
    public var hasSufficientData: Bool
}

public struct CompletionProjection: Codable, Hashable, Sendable {
    public var label: String
    public var wordsPerDay: Double
    public var projectedDate: Date?
    public var daysRemaining: Int?
    public var isSufficient: Bool
}

public struct ProjectStatistics: Codable, Hashable, Sendable {
    public var project: Project
    public var netWords: Int
    public var wordsAdded: Int
    public var wordsRemoved: Int
    public var totalActiveSeconds: Double
    public var sessionCount: Int
    public var writingDays: Int
    public var averageWordsPerDay: Double
    public var averageWordsPerSession: Double
    public var lastActivity: Date?
    public var projections: [CompletionProjection]

    public var wordsRemaining: Int? {
        guard let target = project.targetWordCount else { return nil }
        return max(0, target - project.currentWordCount)
    }

    public var progress: Double? { project.progressFraction }

    public var wordsPerHour: Double? {
        guard totalActiveSeconds > 0 else { return nil }
        return Double(netWords) / (totalActiveSeconds / 3600)
    }
}

public struct GoalProgress: Identifiable, Hashable, Sendable {
    public var goal: Goal
    public var currentValue: Double
    public var fraction: Double
    public var isComplete: Bool

    public var id: String { goal.id }
}
