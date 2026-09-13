import Foundation

/// One session plotted on a scatter chart.
public struct SessionPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let activeMinutes: Double
    public let netWords: Int
    /// Typing pace in words per minute, derived from document character growth.
    public let pace: Double?
    public let sessionType: SessionType
    public let applicationID: String?
    public let projectID: String?
}

/// A cell in the day-of-week × hour matrix.
public struct HourWeekdayCell: Identifiable, Hashable, Sendable {
    public var id: Int { weekday * 100 + hour }
    public let weekday: Int
    public let hour: Int
    public let words: Int
    public let activeSeconds: Double
}

/// A single day's activity for one session type.
public struct SessionTypeDay: Identifiable, Hashable, Sendable {
    public var id: String { "\(dayKey)-\(type.rawValue)" }
    public let dayKey: String
    public let date: Date
    public let type: SessionType
    public let words: Int
    public let activeSeconds: Double
}

/// A single day's words for one project.
public struct ProjectDayWords: Identifiable, Hashable, Sendable {
    public var id: String { "\(dayKey)-\(projectID ?? "none")" }
    public let dayKey: String
    public let date: Date
    public let projectID: String?
    public let words: Int
}

/// A run of consecutive writing days.
public struct StreakRun: Identifiable, Hashable, Sendable {
    public var id: String { "\(start.timeIntervalSince1970)" }
    public let start: Date
    public let end: Date
    public let length: Int
    public let isCurrent: Bool
}

/// A derived typing-pace sample.
public struct PacePoint: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public let date: Date
    public let pace: Double
}

/// A day's added and removed word totals.
public struct AddedRemovedPoint: Identifiable, Hashable, Sendable {
    public var id: String { dayKey }
    public let dayKey: String
    public let date: Date
    public let added: Int
    public let removed: Int
}

/// A point on a cumulative project word-count line.
public struct CumulativePoint: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public let date: Date
    public let words: Int
}

/// A dashed projection line for a project.
public struct ProjectionLine: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let points: [CumulativePoint]
    public let projectedDate: Date?
}

/// Word-count history for one document.
public struct DocumentWordSeries: Identifiable, Hashable, Sendable {
    public var id: String { documentID }
    public let documentID: String
    public let displayName: String
    public let points: [CumulativePoint]
}

/// A month cell in the months-by-years grid.
public struct MonthlyYearCell: Identifiable, Hashable, Sendable {
    public var id: String { "\(year)-\(month)" }
    public let year: Int
    public let month: Int
    public let words: Int
}

/// Words per year and project type.
public struct YearTypeWords: Identifiable, Hashable, Sendable {
    public var id: String { "\(year)-\(type.rawValue)" }
    public let year: String
    public let type: ProjectType
    public let words: Int
}

/// This week vs last week, by weekday.
public struct WeekdayMomentum: Identifiable, Hashable, Sendable {
    public var id: Int { weekday }
    public let weekday: Int
    public let thisWeek: Int
    public let lastWeek: Int
}
