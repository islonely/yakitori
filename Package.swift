// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WritingTracker",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "WritingTrackerCore", targets: ["WritingTrackerCore"]),
        .executable(name: "WritingTracker", targets: ["WritingTrackerApp"])
    ],
    targets: [
        .target(
            name: "WritingTrackerCore",
            path: "Sources/WritingTrackerCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "WritingTrackerApp",
            dependencies: ["WritingTrackerCore"],
            path: "Sources/WritingTrackerApp"
        ),
        .testTarget(
            name: "WritingTrackerCoreTests",
            dependencies: ["WritingTrackerCore"],
            path: "Tests/WritingTrackerCoreTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
