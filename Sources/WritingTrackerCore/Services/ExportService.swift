import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json

    public var id: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
}

public enum ExportScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case sessions
    case dailyStatistics
    case projects
    case wordCountSnapshots

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All data"
        case .sessions: return "Sessions"
        case .dailyStatistics: return "Daily statistics"
        case .projects: return "Projects"
        case .wordCountSnapshots: return "Word-count snapshots"
        }
    }
}

public struct ExportResult {
    public let data: Data
    public let suggestedFileName: String
    public let mimeType: String
}

public final class ExportService {
    private let database: Database
    private let statistics: StatisticsService
    private let dateProvider: DateProviding

    public init(database: Database, statistics: StatisticsService, dateProvider: DateProviding = SystemDateProvider()) {
        self.database = database
        self.statistics = statistics
        self.dateProvider = dateProvider
    }

    public func export(scope: ExportScope, format: ExportFormat) throws -> ExportResult {
        switch format {
        case .csv:
            return try exportCSV(scope: scope)
        case .json:
            return try exportJSON(scope: scope)
        }
    }

    public func write(_ result: ExportResult, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(result.suggestedFileName)
        try result.data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - CSV

    private func exportCSV(scope: ExportScope) throws -> ExportResult {
        switch scope {
        case .sessions, .all:
            let sessions = try SessionRepository(database: database).all()
            let csv = sessionsCSV(sessions)
            return ExportResult(data: Data(csv.utf8), suggestedFileName: "sessions.csv", mimeType: "text/csv")
        case .dailyStatistics:
            let aggregates = try DailyAggregateRepository(database: database).all()
            return ExportResult(data: Data(dailyCSV(aggregates).utf8), suggestedFileName: "daily-statistics.csv", mimeType: "text/csv")
        case .projects:
            let projects = try ProjectRepository(database: database).all()
            return ExportResult(data: Data(projectsCSV(projects).utf8), suggestedFileName: "projects.csv", mimeType: "text/csv")
        case .wordCountSnapshots:
            let snapshots = try WordCountSnapshotRepository(database: database).all()
            return ExportResult(data: Data(snapshotsCSV(snapshots).utf8), suggestedFileName: "word-count-snapshots.csv", mimeType: "text/csv")
        }
    }

    private func sessionsCSV(_ sessions: [Session]) -> String {
        var lines = ["id,project_id,application_id,document_id,started_at,ended_at,active_seconds,focus_seconds,starting_word_count,ending_word_count,net_word_change,session_type,notes"]
        let iso = ISO8601DateFormatter()
        for s in sessions {
            lines.append([
                csv(s.id), csv(s.projectID), csv(s.applicationID), csv(s.documentID),
                csv(iso.string(from: s.startedAt)), csv(s.endedAt.map { iso.string(from: $0) }),
                csv(String(s.activeSeconds)), csv(String(s.focusSeconds)),
                csv(s.startingWordCount.map(String.init)), csv(s.endingWordCount.map(String.init)),
                csv(s.netWordChange.map(String.init)), csv(s.sessionType.rawValue), csv(s.notes)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func dailyCSV(_ aggregates: [DailyAggregate]) -> String {
        var lines = ["date,words_added,words_removed,net_words,active_seconds,focus_seconds,sessions,projects"]
        for a in aggregates {
            lines.append([
                csv(a.dayKey), csv(String(a.wordsAdded)), csv(String(a.wordsRemoved)),
                csv(String(a.netWords)), csv(String(a.activeSeconds)), csv(String(a.focusSeconds)),
                csv(String(a.sessionCount)), csv(String(a.projectCount))
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func projectsCSV(_ projects: [Project]) -> String {
        var lines = ["id,title,type,status,target_word_count,starting_word_count,current_word_count,created_at,started_at,completed_at"]
        let iso = ISO8601DateFormatter()
        for p in projects {
            lines.append([
                csv(p.id), csv(p.title), csv(p.type.rawValue), csv(p.status.rawValue),
                csv(p.targetWordCount.map(String.init)), csv(String(p.startingWordCount)),
                csv(String(p.currentWordCount)), csv(iso.string(from: p.createdAt)),
                csv(p.startedAt.map { iso.string(from: $0) }), csv(p.completedAt.map { iso.string(from: $0) })
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func snapshotsCSV(_ snapshots: [WordCountSnapshot]) -> String {
        var lines = ["timestamp,document_id,project_id,word_count,character_count,page_count,source"]
        let iso = ISO8601DateFormatter()
        for s in snapshots {
            lines.append([
                csv(iso.string(from: s.timestamp)), csv(s.documentID), csv(s.projectID),
                csv(String(s.wordCount)), csv(s.characterCount.map(String.init)),
                csv(s.pageCount.map(String.init)), csv(s.source)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csv(_ value: String?) -> String {
        guard let value else { return "" }
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - JSON

    private func exportJSON(scope: ExportScope) throws -> ExportResult {
        // The JSON export always contains the complete structured data set so a
        // user can fully reconstruct their history (privacy-safe: no text).
        let document = ExportDocument(
            exportedAt: dateProvider.now,
            schemaVersion: 1,
            settings: (try? SettingsRepository(database: database).load()) ?? .default,
            projects: try ProjectRepository(database: database).all(),
            documents: try DocumentRepository(database: database).all(),
            applications: try WritingApplicationRepository(database: database).all(),
            sessions: try SessionRepository(database: database).all(),
            activityEvents: try ActivityEventRepository(database: database).events(in: DateInterval(start: .distantPast, end: .distantFuture)),
            wordCountSnapshots: try WordCountSnapshotRepository(database: database).all(),
            dailyAggregates: try DailyAggregateRepository(database: database).all(),
            goals: try GoalRepository(database: database).all(),
            milestones: try MilestoneRepository(database: database).all(),
            associationRules: try AssociationRuleRepository(database: database).all()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        return ExportResult(data: data, suggestedFileName: "writing-tracker-export.json", mimeType: "application/json")
    }
}

public struct ExportDocument: Codable {
    public var exportedAt: Date
    public var schemaVersion: Int
    public var settings: UserSettings
    public var projects: [Project]
    public var documents: [Document]
    public var applications: [WritingApplication]
    public var sessions: [Session]
    public var activityEvents: [ActivityEvent]
    public var wordCountSnapshots: [WordCountSnapshot]
    public var dailyAggregates: [DailyAggregate]
    public var goals: [Goal]
    public var milestones: [Milestone]
    public var associationRules: [AssociationRule]
}
