import XCTest
@testable import WritingTrackerCore

final class SocialServiceTests: XCTestCase {
    private var database: SQLiteDatabase!
    private var statistics: StatisticsService!
    private var backendURL: URL!
    private let now = TestSupport.date("2026-09-08T21:00:00-04:00")

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        statistics = StatisticsService(
            database: database,
            dateProvider: MutableDateProvider(now),
            calendarContext: TestSupport.calendar()
        )
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yakitori-social-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        backendURL = dir.appendingPathComponent("community.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: backendURL.deletingLastPathComponent())
        database = nil
        statistics = nil
        super.tearDown()
    }

    private func makeService() -> SocialService {
        SocialService(
            database: database,
            statistics: statistics,
            backend: JSONFileSocialBackend(url: backendURL),
            dateProvider: MutableDateProvider(now)
        )
    }

    private func makeProfile(id: String, name: String, words: Int, current: Bool = false, sample: Bool = false) -> CommunityProfile {
        CommunityProfile(
            id: id,
            displayName: name,
            isCurrentUser: current,
            stats: PublicStats(
                allTimeWords: words, wordsThisWeek: words / 10, wordsThisMonth: words / 3,
                activeSeconds: Double(words) / 10, sessions: words / 100, writingDays: 10,
                currentStreak: 3, longestStreak: 20, updatedAt: now
            ),
            isSample: sample
        )
    }

    func testJSONBackendRoundTrip() throws {
        let backend = JSONFileSocialBackend(url: backendURL)
        var data = CommunityData()
        data.profiles = [makeProfile(id: "a", name: "A", words: 100)]
        data.followedProfileIDs = ["a"]
        try backend.save(data)
        let loaded = try backend.load()
        XCTAssertEqual(loaded.profiles.first?.displayName, "A")
        XCTAssertEqual(loaded.followedProfileIDs, ["a"])
    }

    func testPublishSelfAppearsOnLeaderboard() throws {
        let service = makeService()
        try service.publishSelf(displayName: "Adam")
        let entries = service.leaderboard(kind: .allTimeWords)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries.first?.profile.isCurrentUser ?? false)
        XCTAssertEqual(entries.first?.profile.displayName, "Adam")
    }

    func testLeaderboardSortsDescending() throws {
        let backend = JSONFileSocialBackend(url: backendURL)
        var data = CommunityData()
        data.profiles = [
            makeProfile(id: "low", name: "Low", words: 100),
            makeProfile(id: "high", name: "High", words: 900),
            makeProfile(id: "mid", name: "Mid", words: 500)
        ]
        try backend.save(data)
        let entries = makeService().leaderboard(kind: .allTimeWords)
        XCTAssertEqual(entries.map(\.profile.displayName), ["High", "Mid", "Low"])
        XCTAssertEqual(entries.map(\.rank), [1, 2, 3])
    }

    func testFollowAndUnfollowPersist() throws {
        let backend = JSONFileSocialBackend(url: backendURL)
        var data = CommunityData()
        data.profiles = [makeProfile(id: "friend", name: "Friend", words: 400)]
        try backend.save(data)

        let service = makeService()
        XCTAssertFalse(service.isFollowing("friend"))
        try service.follow("friend")
        XCTAssertTrue(service.isFollowing("friend"))
        XCTAssertEqual(service.followedProfiles().map(\.id), ["friend"])
        try service.unfollow("friend")
        XCTAssertFalse(service.isFollowing("friend"))
    }

    func testComparisonContainsRows() throws {
        let backend = JSONFileSocialBackend(url: backendURL)
        var data = CommunityData()
        data.profiles = [makeProfile(id: "friend", name: "Friend", words: 400)]
        try backend.save(data)
        let service = makeService()
        try service.publishSelf(displayName: "Me")

        let friend = service.profile(id: "friend")!
        let rows = service.comparison(with: friend)
        XCTAssertEqual(rows.count, 8)
        XCTAssertTrue(rows.contains { $0.label == "All-time words" })
    }

    func testSamplesMergeOnlyWhenEnabled() throws {
        let service = makeService()
        try service.publishSelf(displayName: "Me")
        XCTAssertEqual(service.leaderboard(kind: .allTimeWords).count, 1)

        var settings = UserSettings.default
        settings.showSampleCommunity = true
        try SettingsRepository(database: database).save(settings)

        let entries = makeService().leaderboard(kind: .allTimeWords)
        XCTAssertGreaterThan(entries.count, 1)
        XCTAssertTrue(entries.contains { $0.profile.isSample })
    }

    func testRemoveSelf() throws {
        let service = makeService()
        try service.publishSelf(displayName: "Me")
        XCTAssertEqual(service.leaderboard(kind: .allTimeWords).count, 1)
        try service.removeSelf()
        XCTAssertTrue(service.leaderboard(kind: .allTimeWords).isEmpty)
    }
}
