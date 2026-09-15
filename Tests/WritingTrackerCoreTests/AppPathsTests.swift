import XCTest

@testable import WritingTrackerCore

final class AppPathsTests: XCTestCase {
    private var scratch: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        scratch = fileManager.temporaryDirectory
            .appendingPathComponent("AppPathsTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: scratch)
    }

    func testExplicitOverrideWins() {
        let override = scratch.appendingPathComponent("custom", isDirectory: true)
        let resolved = AppPaths.resolveDataDirectory(
            environment: ["YAKITORI_DATA_DIR": override.path],
            fileManager: fileManager,
            iCloudContainer: nil,
            localSupport: scratch
        )
        XCTAssertEqual(resolved.standardizedFileURL, override.standardizedFileURL)
        XCTAssertTrue(fileManager.fileExists(atPath: resolved.path))
    }

    func testDisabledICloudFallsBackToApplicationSupport() {
        let support = scratch.appendingPathComponent("support", isDirectory: true)
        let resolved = AppPaths.resolveDataDirectory(
            environment: ["YAKITORI_USE_ICLOUD": "0"],
            fileManager: fileManager,
            iCloudContainer: nil,
            localSupport: support
        )
        XCTAssertEqual(resolved.lastPathComponent, "Yakitori")
        XCTAssertTrue(resolved.path.hasPrefix(support.standardizedFileURL.path))
        XCTAssertFalse(AppPaths.isCloudPath(resolved))
    }

    func testICloudContainerIsUsedAndLocalDatabaseIsCopied() throws {
        let support = scratch.appendingPathComponent("support", isDirectory: true)
        // A path shaped like the real iCloud Drive container so the cloud
        // detection behaves as it does in production.
        let iCloud = scratch.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs",
            isDirectory: true
        )

        let localDirectory = support.appendingPathComponent("Yakitori", isDirectory: true)
        try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try Data("existing-database".utf8).write(
            to: localDirectory.appendingPathComponent("Yakitori.sqlite")
        )
        try Data("{}".utf8).write(
            to: localDirectory.appendingPathComponent("community.json")
        )

        let resolved = AppPaths.resolveDataDirectory(
            environment: [:],
            fileManager: fileManager,
            iCloudContainer: iCloud,
            localSupport: support
        )

        let expected = iCloud.appendingPathComponent("Yakitori", isDirectory: true)
        XCTAssertEqual(resolved.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertTrue(AppPaths.isCloudPath(resolved))

        // The database is copied into iCloud…
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: resolved.appendingPathComponent("Yakitori.sqlite").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: resolved.appendingPathComponent("community.json").path
            )
        )
        // …and the original local copy is deliberately kept.
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: localDirectory.appendingPathComponent("Yakitori.sqlite").path
            )
        )
    }

    func testShouldUseICloudHonorsEnvironmentAndDefaultsOn() {
        XCTAssertFalse(
            AppPaths.shouldUseICloud(
                environment: ["YAKITORI_USE_ICLOUD": "false"],
                fileManager: fileManager
            )
        )
        XCTAssertTrue(
            AppPaths.shouldUseICloud(
                environment: ["YAKITORI_USE_ICLOUD": "1"],
                fileManager: fileManager
            )
        )
    }

    func testCloudBackedPathDetection() {
        XCTAssertTrue(
            SQLiteDatabase.isCloudBackedPath(
                "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/Yakitori/Yakitori.sqlite"
            )
        )
        XCTAssertFalse(
            SQLiteDatabase.isCloudBackedPath(
                "/Users/x/Library/Application Support/Yakitori/Yakitori.sqlite"
            )
        )
    }
}
