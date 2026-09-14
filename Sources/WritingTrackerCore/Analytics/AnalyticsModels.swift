import Foundation

// MARK: - 1. Session duration distribution

public struct SessionDurationDistribution: Sendable {
    public let bins: [HistogramBin]
    public let summary: DistributionSummary
    /// Total sessions considered (after excluding invalid durations).
    public let sessionCount: Int

    public var isEmpty: Bool { sessionCount == 0 }
}

// MARK: - 2. Daily output distribution

public enum DailyOutputMetric: String, CaseIterable, Identifiable, Sendable {
    case netWords
    case grossWorked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .netWords: return "Net words"
        case .grossWorked: return "Gross words worked"
        }
    }

    /// Gross worked is derived from added + removed (estimated where exact edits
    /// are unavailable); net words come straight from document word counts.
    public var isEstimated: Bool { self == .grossWorked }
}

public struct DailyOutputDistribution: Sendable {
    public let metric: DailyOutputMetric
    public let bins: [HistogramBin]
    public let summary: DistributionSummary
    public let writingDayCount: Int

    public var isEmpty: Bool { writingDayCount == 0 }
}

// MARK: - 3. Productivity by session length

public struct SessionLengthProductivityBin: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let lowerMinutes: Double
    public let upperMinutes: Double?
    public let medianWordsPerHour: Double
    public let p25WordsPerHour: Double
    public let p75WordsPerHour: Double
    public let sampleCount: Int
    public let isSufficient: Bool
}

public struct SessionLengthProductivity: Sendable {
    public let bins: [SessionLengthProductivityBin]
    public let minimumSampleSize: Int

    public var hasSufficientBins: Bool { bins.contains { $0.isSufficient } }
}

// MARK: - 4. Goal performance history

public struct GoalPeriodResult: Identifiable, Hashable, Sendable {
    public var id: String
    public let goalID: String
    public let label: String
    public let start: Date
    public let end: Date
    public let metric: GoalMetric
    public let target: Double
    public let actual: Double

    /// Attainment as a percentage of the target. Zero when the target is zero.
    public var attainment: Double { target > 0 ? actual / target * 100 : 0 }
}

public struct GoalPerformanceHistory: Sendable {
    public let period: GoalPeriod
    public let metric: GoalMetric
    public let results: [GoalPeriodResult]
    public let met: Int
    public let missed: Int
    public let successRate: Double
    public let medianAttainment: Double
    public let averageAttainment: Double
    public let longestSuccessRun: Int

    public var isEmpty: Bool { results.isEmpty }
}

// MARK: - 5. Project velocity

public enum VelocityGranularity: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    var rollingWindow: Int {
        switch self {
        case .daily: return 7
        case .weekly: return 4
        }
    }
}

public struct VelocityPoint: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public let date: Date
    public let words: Int
    public let rollingAverage: Double?
}

public struct ProjectVelocity: Sendable {
    public let projectID: String
    public let granularity: VelocityGranularity
    public let points: [VelocityPoint]

    public var hasSufficientData: Bool { points.count >= 2 }

    public var hasRollingSeries: Bool { points.contains { $0.rollingAverage != nil } }
}

// MARK: - 6. Writing cadence

public struct WritingCadence: Sendable {
    public let bins: [HistogramBin]
    public let summary: DistributionSummary
    /// Number of gaps between sessions (one fewer than the session count).
    public let gapCount: Int

    public var isEmpty: Bool { gapCount == 0 }
}

// MARK: - 7. Project effort by phase

public struct PhaseEffortSlice: Identifiable, Hashable, Sendable {
    public var id: String { type.rawValue }
    public let type: SessionType
    public let activeSeconds: Double
    public let fraction: Double
}

public struct ProjectPhaseEffort: Identifiable, Hashable, Sendable {
    public var id: String { projectID }
    public let projectID: String
    public let projectName: String
    public let slices: [PhaseEffortSlice]
    public let totalActiveSeconds: Double

    public var isEmpty: Bool { totalActiveSeconds <= 0 }
}

// MARK: - 8. Cumulative lifetime output

public enum CumulativeOutputMetric: String, CaseIterable, Identifiable, Sendable {
    case netWords
    case grossWorked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .netWords: return "Net manuscript words"
        case .grossWorked: return "Gross words worked"
        }
    }

    public var isEstimated: Bool { self == .grossWorked }
}

public struct CumulativeOutputPoint: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public let date: Date
    public let value: Int
}

// MARK: - 9. Productivity variability

public struct VariabilityPoint: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public let date: Date
    public let observationCount: Int
    public let mean: Double
    public let standardDeviation: Double
    /// Coefficient of variation, or nil when the mean is zero.
    public let coefficientOfVariation: Double?
}

public struct OutputVariability: Sendable {
    public let window: Int
    public let points: [VariabilityPoint]
    /// True when the series is built from writing days (days with sessions).
    public let usesWritingDaysOnly: Bool

    public var isEmpty: Bool { points.isEmpty }
}

// MARK: - 10. Productivity by work type

public struct WorkTypeProductivity: Identifiable, Hashable, Sendable {
    public var id: String { type.rawValue }
    public let type: SessionType
    public let medianWordsPerHour: Double?
    public let meanWordsPerHour: Double?
    public let p25WordsPerHour: Double?
    public let p75WordsPerHour: Double?
    public let sampleCount: Int
    public let isSufficient: Bool
}
