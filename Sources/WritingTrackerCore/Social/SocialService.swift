import Foundation

/// Storage abstraction for community/leaderboard data. The placeholder is a
/// local JSON file; the same shape can later come from a server.
public protocol SocialBackend: AnyObject {
    func load() throws -> CommunityData
    func save(_ data: CommunityData) throws
    var storageURL: URL? { get }
}

/// Local JSON placeholder backend, stored next to the database.
public final class JSONFileSocialBackend: SocialBackend {
    private let url: URL
    private let fileManager = FileManager.default

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(url: URL = AppPaths.communityDataURL) {
        self.url = url
    }

    public var storageURL: URL? { url }

    public func load() throws -> CommunityData {
        guard fileManager.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return .empty }
        return try decoder.decode(CommunityData.self, from: data)
    }

    public func save(_ data: CommunityData) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(data).write(to: url, options: .atomic)
    }
}

/// Placeholder entries used only when the user explicitly enables "Show sample
/// leaderboard entries". They make the board structure visible until the online
/// service exists, and are clearly flagged as samples.
public enum SampleCommunity {
    public static func profiles(now: Date) -> [CommunityProfile] {
        func stats(_ words: Int, _ week: Int, _ month: Int, _ hours: Double, _ sessions: Int, _ days: Int, _ current: Int, _ longest: Int) -> PublicStats {
            PublicStats(
                allTimeWords: words,
                wordsThisWeek: week,
                wordsThisMonth: month,
                activeSeconds: hours * 3600,
                sessions: sessions,
                writingDays: days,
                currentStreak: current,
                longestStreak: longest,
                updatedAt: now
            )
        }
        return [
            CommunityProfile(id: "sample-1", displayName: "A. Rivera", isCurrentUser: false,
                             stats: stats(412_300, 6_240, 24_900, 512, 730, 402, 12, 63), isSample: true),
            CommunityProfile(id: "sample-2", displayName: "M. Chen", isCurrentUser: false,
                             stats: stats(268_940, 4_105, 18_220, 388, 611, 344, 5, 41), isSample: true),
            CommunityProfile(id: "sample-3", displayName: "J. Okafor", isCurrentUser: false,
                             stats: stats(1_204_880, 9_800, 41_300, 1_204, 1_530, 890, 27, 120), isSample: true),
            CommunityProfile(id: "sample-4", displayName: "S. Lindqvist", isCurrentUser: false,
                             stats: stats(96_120, 2_050, 9_140, 150, 233, 140, 3, 22), isSample: true)
        ]
    }
}

/// Local-first community and leaderboard service.
///
/// Publishing is opt-in. Only aggregate numbers are written — never document
/// names, project names, paths, or manuscript text.
public final class SocialService {
    public static let currentUserID = "local-user"

    private let statistics: StatisticsService
    private let backend: SocialBackend
    private let settingsRepository: SettingsRepository
    private let dateProvider: DateProviding

    public init(
        database: Database,
        statistics: StatisticsService,
        backend: SocialBackend? = nil,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.statistics = statistics
        self.backend = backend ?? JSONFileSocialBackend()
        self.settingsRepository = SettingsRepository(database: database)
        self.dateProvider = dateProvider
    }

    public var storageURL: URL? { backend.storageURL }

    public func currentPublicStats() -> PublicStats {
        let now = dateProvider.now
        let lifetime = statistics.lifetimeStatistics()
        let streaks = statistics.streakStatistics()
        return PublicStats(
            allTimeWords: lifetime.lifetimeNetWords,
            wordsThisWeek: statistics.weeklyStatistics(containing: now).netWords,
            wordsThisMonth: statistics.monthlyStatistics(containing: now).netWords,
            activeSeconds: lifetime.totalActiveSeconds,
            sessions: lifetime.totalSessions,
            writingDays: lifetime.writingDays,
            currentStreak: streaks.currentStreak,
            longestStreak: streaks.longestStreak,
            updatedAt: now
        )
    }

    /// Loads community data, optionally merging clearly-labelled sample entries.
    public func loadCommunity() -> CommunityData {
        var data = (try? backend.load()) ?? .empty
        let settings = (try? settingsRepository.load()) ?? .default
        if settings.showSampleCommunity {
            let existing = Set(data.profiles.map(\.id))
            data.profiles.append(contentsOf: SampleCommunity.profiles(now: dateProvider.now).filter { !existing.contains($0.id) })
        }
        return data
    }

    /// Writes the current writer's aggregate stats. No-op guard is the caller's.
    public func publishSelf(displayName: String) throws {
        var data = (try? backend.load()) ?? .empty
        let profile = CommunityProfile(
            id: Self.currentUserID,
            displayName: displayName,
            isCurrentUser: true,
            stats: currentPublicStats()
        )
        data.profiles.removeAll { $0.id == Self.currentUserID }
        data.profiles.append(profile)
        data.updatedAt = dateProvider.now
        try backend.save(data)
    }

    public func removeSelf() throws {
        var data = (try? backend.load()) ?? .empty
        data.profiles.removeAll { $0.id == Self.currentUserID }
        data.updatedAt = dateProvider.now
        try backend.save(data)
    }

    public func leaderboard(kind: LeaderboardKind) -> [LeaderboardEntry] {
        loadCommunity().profiles
            .map { ($0, kind.value($0.stats)) }
            .sorted { $0.1 > $1.1 }
            .enumerated()
            .map { LeaderboardEntry(rank: $0.offset + 1, profile: $0.element.0, value: $0.element.1) }
    }

    public func allLeaderboards() -> [(kind: LeaderboardKind, entries: [LeaderboardEntry])] {
        LeaderboardKind.allCases.map { ($0, leaderboard(kind: $0)) }
    }

    public func profiles() -> [CommunityProfile] {
        loadCommunity().profiles
    }

    public func profile(id: String) -> CommunityProfile? {
        loadCommunity().profiles.first { $0.id == id }
    }

    public func followedProfiles() -> [CommunityProfile] {
        let data = loadCommunity()
        return data.profiles.filter { data.followedProfileIDs.contains($0.id) }
    }

    public func isFollowing(_ id: String) -> Bool {
        loadCommunity().followedProfileIDs.contains(id)
    }

    public func follow(_ id: String) throws { try setFollow(id, true) }
    public func unfollow(_ id: String) throws { try setFollow(id, false) }

    private func setFollow(_ id: String, _ follow: Bool) throws {
        var data = (try? backend.load()) ?? .empty
        if follow {
            if !data.followedProfileIDs.contains(id) { data.followedProfileIDs.append(id) }
        } else {
            data.followedProfileIDs.removeAll { $0 == id }
        }
        data.updatedAt = dateProvider.now
        try backend.save(data)
    }

    public func comparison(with profile: CommunityProfile) -> [WriterComparison] {
        guard let self = loadCommunity().currentUserProfile else { return [] }
        return [
            WriterComparison(label: "Words this week", you: Double(self.stats.wordsThisWeek), them: Double(profile.stats.wordsThisWeek), isTime: false),
            WriterComparison(label: "Words this month", you: Double(self.stats.wordsThisMonth), them: Double(profile.stats.wordsThisMonth), isTime: false),
            WriterComparison(label: "All-time words", you: Double(self.stats.allTimeWords), them: Double(profile.stats.allTimeWords), isTime: false),
            WriterComparison(label: "Active time", you: self.stats.activeSeconds, them: profile.stats.activeSeconds, isTime: true),
            WriterComparison(label: "Sessions", you: Double(self.stats.sessions), them: Double(profile.stats.sessions), isTime: false),
            WriterComparison(label: "Writing days", you: Double(self.stats.writingDays), them: Double(profile.stats.writingDays), isTime: false),
            WriterComparison(label: "Current streak", you: Double(self.stats.currentStreak), them: Double(profile.stats.currentStreak), isTime: false),
            WriterComparison(label: "Longest streak", you: Double(self.stats.longestStreak), them: Double(profile.stats.longestStreak), isTime: false)
        ]
    }
}
