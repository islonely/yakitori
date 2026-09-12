import Foundation

/// A half-open or closed time range used to describe activity within a session.
public struct TimeRange: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public var clamped: TimeRange? {
        duration > 0 ? self : nil
    }

    /// Splits this range into per-day pieces using the supplied calendar.
    public func splitByDay(calendar: Calendar) -> [(day: Date, range: TimeRange)] {
        guard duration > 0 else { return [] }
        var result: [(Date, TimeRange)] = []
        var cursor = start
        var safety = 0
        while cursor < end && safety < 5000 {
            safety += 1
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let sliceEnd = min(nextDay, end)
            result.append((dayStart, TimeRange(start: cursor, end: sliceEnd)))
            cursor = sliceEnd
        }
        return result
    }
}

/// A writing application known to the tracker.
public struct WritingApplication: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var bundleIdentifier: String
    public var displayName: String
    public var iconReference: String?
    public var adapterType: AdapterType
    public var category: ApplicationCategory
    public var enabled: Bool
    public var automaticTrackingEnabled: Bool
    public var configuration: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        bundleIdentifier: String,
        displayName: String,
        iconReference: String? = nil,
        adapterType: AdapterType = .generic,
        category: ApplicationCategory = .writing,
        enabled: Bool = true,
        automaticTrackingEnabled: Bool = true,
        configuration: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.iconReference = iconReference
        self.adapterType = adapterType
        self.category = category
        self.enabled = enabled
        self.automaticTrackingEnabled = automaticTrackingEnabled
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A writing project (novel, article, thesis, blog, …).
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var type: ProjectType
    public var description: String?
    public var status: ProjectStatus
    public var targetWordCount: Int?
    public var startingWordCount: Int
    public var currentWordCount: Int
    public var deadline: Date?
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var archivedAt: Date?

    public init(
        id: String = UUID().uuidString,
        title: String,
        type: ProjectType = .novel,
        description: String? = nil,
        status: ProjectStatus = .idea,
        targetWordCount: Int? = nil,
        startingWordCount: Int = 0,
        currentWordCount: Int = 0,
        deadline: Date? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.description = description
        self.status = status
        self.targetWordCount = targetWordCount
        self.startingWordCount = startingWordCount
        self.currentWordCount = currentWordCount
        self.deadline = deadline
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
    }

    /// Net manuscript change relative to the starting word count.
    public var netWordChange: Int { currentWordCount - startingWordCount }

    public var progressFraction: Double? {
        guard let target = targetWordCount, target > 0 else { return nil }
        return min(1.0, max(0.0, Double(currentWordCount) / Double(target)))
    }
}

/// A document opened in a writing application.
public struct Document: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var projectID: String?
    public var applicationID: String?
    public var displayName: String
    public var stableIdentifier: String?
    public var filePath: String?
    public var createdAt: Date
    public var lastSeenAt: Date

    public init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        applicationID: String? = nil,
        displayName: String,
        stableIdentifier: String? = nil,
        filePath: String? = nil,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.applicationID = applicationID
        self.displayName = displayName
        self.stableIdentifier = stableIdentifier
        self.filePath = filePath
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

/// A tracked writing session.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var projectID: String?
    public var documentID: String?
    public var applicationID: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var activeSeconds: Double
    public var focusSeconds: Double
    public var startingWordCount: Int?
    public var endingWordCount: Int?
    public var wordsAdded: Int?
    public var wordsRemoved: Int?
    public var netWordChange: Int?
    public var sessionType: SessionType
    public var notes: String?
    /// Exact activity ranges, used for accurate per-day aggregation and timezone/DST correctness.
    public var activeRanges: [TimeRange]
    public var focusRanges: [TimeRange]
    public var isRecovered: Bool

    public init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        documentID: String? = nil,
        applicationID: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        activeSeconds: Double = 0,
        focusSeconds: Double = 0,
        startingWordCount: Int? = nil,
        endingWordCount: Int? = nil,
        wordsAdded: Int? = nil,
        wordsRemoved: Int? = nil,
        netWordChange: Int? = nil,
        sessionType: SessionType = .unknown,
        notes: String? = nil,
        activeRanges: [TimeRange] = [],
        focusRanges: [TimeRange] = [],
        isRecovered: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.documentID = documentID
        self.applicationID = applicationID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.focusSeconds = focusSeconds
        self.startingWordCount = startingWordCount
        self.endingWordCount = endingWordCount
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
        self.netWordChange = netWordChange
        self.sessionType = sessionType
        self.notes = notes
        self.activeRanges = activeRanges
        self.focusRanges = focusRanges
        self.isRecovered = isRecovered
    }

    public var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var isOpen: Bool { endedAt == nil }

    /// Net manuscript change. Nil when word counts are unavailable.
    public var computedNetWordChange: Int? {
        guard let start = startingWordCount, let end = endingWordCount else { return nil }
        return end - start
    }

    public var wordsPerMinute: Double? {
        guard activeSeconds > 0, let net = netWordChange else { return nil }
        let minutes = activeSeconds / 60.0
        guard minutes > 0 else { return nil }
        return Double(net) / minutes
    }
}

/// A raw activity signal. Never contains typed content.
public struct ActivityEvent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var timestamp: Date
    public var applicationID: String?
    public var eventType: ActivityEventType
    public var sessionID: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        applicationID: String? = nil,
        eventType: ActivityEventType,
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.applicationID = applicationID
        self.eventType = eventType
        self.sessionID = sessionID
        self.metadata = metadata
    }
}

/// A point-in-time word count for a document.
public struct WordCountSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var timestamp: Date
    public var documentID: String?
    public var projectID: String?
    public var wordCount: Int
    public var characterCount: Int?
    public var pageCount: Int?
    public var source: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        documentID: String? = nil,
        projectID: String? = nil,
        wordCount: Int,
        characterCount: Int? = nil,
        pageCount: Int? = nil,
        source: String = "unknown"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.documentID = documentID
        self.projectID = projectID
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.pageCount = pageCount
        self.source = source
    }
}

/// Precomputed per-day totals. Raw sessions remain the source of truth.
public struct DailyAggregate: Codable, Identifiable, Hashable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var date: Date
    public var wordsAdded: Int
    public var wordsRemoved: Int
    public var netWords: Int
    public var activeSeconds: Double
    public var focusSeconds: Double
    public var sessionCount: Int
    public var projectCount: Int
    public var firstSessionAt: Date?
    public var lastSessionAt: Date?

    public init(
        dayKey: String,
        date: Date,
        wordsAdded: Int = 0,
        wordsRemoved: Int = 0,
        netWords: Int = 0,
        activeSeconds: Double = 0,
        focusSeconds: Double = 0,
        sessionCount: Int = 0,
        projectCount: Int = 0,
        firstSessionAt: Date? = nil,
        lastSessionAt: Date? = nil
    ) {
        self.dayKey = dayKey
        self.date = date
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
        self.netWords = netWords
        self.activeSeconds = activeSeconds
        self.focusSeconds = focusSeconds
        self.sessionCount = sessionCount
        self.projectCount = projectCount
        self.firstSessionAt = firstSessionAt
        self.lastSessionAt = lastSessionAt
    }

    public var isWritingDay: Bool { sessionCount > 0 && (netWords != 0 || activeSeconds > 0) }
}

/// A user goal.
public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var projectID: String?
    public var period: GoalPeriod
    public var metric: GoalMetric
    public var target: Double
    public var startDate: Date
    public var endDate: Date?
    public var enabled: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        period: GoalPeriod,
        metric: GoalMetric = .words,
        target: Double,
        startDate: Date = Date(),
        endDate: Date? = nil,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.period = period
        self.metric = metric
        self.target = target
        self.startDate = startDate
        self.endDate = endDate
        self.enabled = enabled
        self.createdAt = createdAt
    }
}

/// A project milestone.
public struct Milestone: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var projectID: String
    public var title: String
    public var targetValue: Double?
    public var metric: GoalMetric?
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        projectID: String,
        title: String,
        targetValue: Double? = nil,
        metric: GoalMetric? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.targetValue = targetValue
        self.metric = metric
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

/// Per-weekday scheduled writing target.
public struct WritingSchedule: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// 1 = Sunday ... 7 = Saturday (matches Foundation weekday values)
    public var weekday: Int
    public var enabled: Bool
    public var targetMinutes: Int?
    public var targetWords: Int?

    public init(
        id: String = UUID().uuidString,
        weekday: Int,
        enabled: Bool = true,
        targetMinutes: Int? = nil,
        targetWords: Int? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.enabled = enabled
        self.targetMinutes = targetMinutes
        self.targetWords = targetWords
    }

    public static func defaultWeek() -> [WritingSchedule] {
        let names = [1, 2, 3, 4, 5, 6, 7]
        return names.map { WritingSchedule(weekday: $0, enabled: true) }
    }
}

/// A project folder/file association rule.
public struct AssociationRule: Codable, Identifiable, Hashable, Sendable {
    public enum RuleType: String, Codable, Sendable {
        case folderPath
        case filePath
        case documentName
        case applicationProject
    }

    public var id: String
    public var projectID: String
    public var type: RuleType
    public var value: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        projectID: String,
        type: RuleType,
        value: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.type = type
        self.value = value
        self.createdAt = createdAt
    }
}

/// Application capabilities exposed by an adapter.
public struct ApplicationCapabilities: Codable, Hashable, Sendable {
    public var activeDocument: Bool
    public var documentPath: Bool
    public var wordCount: Bool
    public var textAccess: Bool
    public var projectDetection: Bool
    public var changeDetection: Bool

    public init(
        activeDocument: Bool,
        documentPath: Bool,
        wordCount: Bool,
        textAccess: Bool = false,
        projectDetection: Bool = false,
        changeDetection: Bool = false
    ) {
        self.activeDocument = activeDocument
        self.documentPath = documentPath
        self.wordCount = wordCount
        self.textAccess = textAccess
        self.projectDetection = projectDetection
        self.changeDetection = changeDetection
    }

    public static let focusAndActivityOnly = ApplicationCapabilities(
        activeDocument: false,
        documentPath: false,
        wordCount: false
    )

    public static let documentOnly = ApplicationCapabilities(
        activeDocument: true,
        documentPath: false,
        wordCount: false
    )

    public static let documentAndWordCount = ApplicationCapabilities(
        activeDocument: true,
        documentPath: true,
        wordCount: true,
        changeDetection: false
    )
}

/// Lightweight description of the active document returned by an adapter.
public struct ActiveDocumentInfo: Codable, Hashable, Sendable {
    public var displayName: String
    public var stableIdentifier: String?
    public var filePath: String?
    public var wordCount: Int?
    public var characterCount: Int?
    public var pageCount: Int?

    public init(
        displayName: String,
        stableIdentifier: String? = nil,
        filePath: String? = nil,
        wordCount: Int? = nil,
        characterCount: Int? = nil,
        pageCount: Int? = nil
    ) {
        self.displayName = displayName
        self.stableIdentifier = stableIdentifier
        self.filePath = filePath
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.pageCount = pageCount
    }
}

/// A snapshot of the frontmost application.
public struct FrontmostApplicationInfo: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var localizedName: String
    public var processIdentifier: Int32

    public init(bundleIdentifier: String?, localizedName: String, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
    }
}
