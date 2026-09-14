import Foundation
import AppKit

/// Privacy-safe diagnostic report.
///
/// Deliberately excludes document names, file paths, project names and any
/// manuscript content. Used by the `--diagnostics` CLI flag and the diagnostic
/// export described in the design document.
public struct DiagnosticReport: Codable, Sendable {
    public var appVersion: String
    public var macOSVersion: String
    public var databasePath: String
    public var databaseWritable: Bool
    public var schemaVersion: Int
    public var projectCount: Int
    public var sessionCount: Int
    public var openSessionCount: Int
    public var applicationCount: Int
    public var aggregateCount: Int
    public var wordInstalled: Bool
    public var wordRunning: Bool
    public var wordWordCountAvailable: Bool
    public var wordDocumentDetected: Bool
    public var generatedAt: Date
}

public final class DiagnosticsService {
    private let database: Database
    private let databaseURL: URL?
    private let permissionProvider: PermissionProviding
    private let registry: AdapterRegistry
    private let dateProvider: DateProviding

    public init(
        database: Database,
        databaseURL: URL? = AppPaths.databaseURL,
        permissionProvider: PermissionProviding = PermissionManager(),
        registry: AdapterRegistry = .shared,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.database = database
        self.databaseURL = databaseURL
        self.permissionProvider = permissionProvider
        self.registry = registry
        self.dateProvider = dateProvider
    }

    public func generate(probeWord: Bool = false) -> DiagnosticReport {
        let migrator = Migrator(database: database)
        let wordAdapter = registry.adapter(forBundleIdentifier: "com.microsoft.Word", adapterType: .word)
        var wordWordCount = false
        var wordDocument = false
        if probeWord, ApplicationLocator.isRunning(bundleIdentifier: "com.microsoft.Word"),
           let document = wordAdapter.activeDocument() {
            wordDocument = true
            wordWordCount = document.wordCount != nil
        }

        let process = ProcessInfo.processInfo
        return DiagnosticReport(
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev",
            macOSVersion: process.operatingSystemVersionString,
            databasePath: databaseURL?.lastPathComponent ?? "(in-memory)",
            databaseWritable: databaseURL.map { FileManager.default.isWritableFile(atPath: $0.path) } ?? true,
            schemaVersion: migrator.currentVersion,
            projectCount: (try? ProjectRepository(database: database).count()) ?? 0,
            sessionCount: (try? SessionRepository(database: database).count()) ?? 0,
            openSessionCount: ((try? SessionRepository(database: database).openSessions()) ?? []).count,
            applicationCount: (try? WritingApplicationRepository(database: database).count()) ?? 0,
            aggregateCount: ((try? DailyAggregateRepository(database: database).all()) ?? []).count,
            wordInstalled: ApplicationLocator.isInstalled(bundleIdentifier: "com.microsoft.Word"),
            wordRunning: ApplicationLocator.isRunning(bundleIdentifier: "com.microsoft.Word"),
            wordWordCountAvailable: wordWordCount,
            wordDocumentDetected: wordDocument,
            generatedAt: dateProvider.now
        )
    }

    public func jsonString(probeWord: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(generate(probeWord: probeWord)) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
