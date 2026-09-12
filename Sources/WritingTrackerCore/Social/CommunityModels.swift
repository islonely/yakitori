import Foundation

/// The aggregate statistics a writer chooses to expose. Never includes document
/// names, project names, paths, or manuscript text.
public struct PublicStats: Codable, Hashable, Sendable {
    public var allTimeWords: Int
    public var wordsThisWeek: Int
    public var wordsThisMonth: Int
    public var activeSeconds: Double
    public var sessions: Int
    public var writingDays: Int
    public var currentStreak: Int
    public var longestStreak: Int
    public var updatedAt: Date

    public init(
        allTimeWords: Int,
        wordsThisWeek: Int,
        wordsThisMonth: Int,
        activeSeconds: Double,
        sessions: Int,
        writingDays: Int,
        currentStreak: Int,
        longestStreak: Int,
        updatedAt: Date
    ) {
        self.allTimeWords = allTimeWords
        self.wordsThisWeek = wordsThisWeek
        self.wordsThisMonth = wordsThisMonth
        self.activeSeconds = activeSeconds
        self.sessions = sessions
        self.writingDays = writingDays
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.updatedAt = updatedAt
    }
}

/// A writer's public presence in the community file. `isCurrentUser` marks the
/// local writer so they can be highlighted and compared against.
public struct CommunityProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var isCurrentUser: Bool
    public var stats: PublicStats
    public var isSample: Bool

    public init(id: String, displayName: String, isCurrentUser: Bool, stats: PublicStats, isSample: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isCurrentUser = isCurrentUser
        self.stats = stats
        self.isSample = isSample
    }

    public var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.first ?? "?") }.joined().uppercased()
    }
}

/// The document stored by a `SocialBackend`. With the placeholder JSON backend
/// this is a single local file; a future server returns the same shape.
public struct CommunityData: Codable, Sendable {
    public var schemaVersion: Int
    public var profiles: [CommunityProfile]
    public var followedProfileIDs: [String]
    public var updatedAt: Date

    public init(schemaVersion: Int = 1, profiles: [CommunityProfile] = [], followedProfileIDs: [String] = [], updatedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.followedProfileIDs = followedProfileIDs
        self.updatedAt = updatedAt
    }

    public static let empty = CommunityData()

    public var currentUserProfile: CommunityProfile? {
        profiles.first { $0.isCurrentUser }
    }
}

/// The different boards a writer can appear on after finishing a session.
public enum LeaderboardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wordsThisWeek
    case wordsThisMonth
    case allTimeWords
    case activeTime
    case currentStreak
    case longestStreak

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wordsThisWeek: return "Words this week"
        case .wordsThisMonth: return "Words this month"
        case .allTimeWords: return "All-time words"
        case .activeTime: return "Active time"
        case .currentStreak: return "Current streak"
        case .longestStreak: return "Longest streak"
        }
    }

    public var isTime: Bool { self == .activeTime }

    public func value(_ stats: PublicStats) -> Double {
        switch self {
        case .wordsThisWeek: return Double(stats.wordsThisWeek)
        case .wordsThisMonth: return Double(stats.wordsThisMonth)
        case .allTimeWords: return Double(stats.allTimeWords)
        case .activeTime: return stats.activeSeconds
        case .currentStreak: return Double(stats.currentStreak)
        case .longestStreak: return Double(stats.longestStreak)
        }
    }

    public func formatted(_ value: Double) -> String {
        switch self {
        case .activeTime:
            return DurationFormatter.short(value)
        case .currentStreak, .longestStreak:
            return "\(Int(value.rounded())) days"
        default:
            return Int(value.rounded()).formatted(.number.grouping(.automatic))
        }
    }
}

public struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    public var id: String { profile.id }
    public let rank: Int
    public let profile: CommunityProfile
    public let value: Double
}

public struct WriterComparison: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let you: Double
    public let them: Double
    public let isTime: Bool

    public var delta: Double { you - them }
    public var formattedYou: String { isTime ? DurationFormatter.short(you) : Int(you.rounded()).formatted(.number.grouping(.automatic)) }
    public var formattedThem: String { isTime ? DurationFormatter.short(them) : Int(them.rounded()).formatted(.number.grouping(.automatic)) }
    public var formattedDelta: String {
        let sign = delta >= 0 ? "+" : "−"
        let magnitude = abs(delta)
        let text = isTime ? DurationFormatter.short(magnitude) : Int(magnitude.rounded()).formatted(.number.grouping(.automatic))
        return "\(sign)\(text)"
    }
}
