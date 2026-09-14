import Foundation
import os

/// Central logging facility.
///
/// Privacy rule: logs may contain application names, document identifiers,
/// timestamps and word-count numbers, but must **never** contain manuscript
/// text, typed characters, clipboard contents, or keystrokes.
public enum Log {
    private static let subsystem = "com.yakitori.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let tracking = Logger(subsystem: subsystem, category: "tracking")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let integrations = Logger(subsystem: subsystem, category: "integrations")
    public static let statistics = Logger(subsystem: subsystem, category: "statistics")
    public static let export = Logger(subsystem: subsystem, category: "export")
    public static let account = Logger(subsystem: subsystem, category: "account")
}

/// Common errors surfaced by the core.
public enum WritingTrackerError: LocalizedError, Equatable {
    case databaseUnavailable(String)
    case databaseCorrupt(String)
    case notFound(String)
    case invalidData(String)
    case migrationFailed(String)
    case permissionDenied(String)
    case integrationUnavailable(String)
    case exportFailed(String)
    case importFailed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .databaseUnavailable(let m): return "Database unavailable: \(m)"
        case .databaseCorrupt(let m): return "Database corrupt: \(m)"
        case .notFound(let m): return "Not found: \(m)"
        case .invalidData(let m): return "Invalid data: \(m)"
        case .migrationFailed(let m): return "Migration failed: \(m)"
        case .permissionDenied(let m): return "Permission denied: \(m)"
        case .integrationUnavailable(let m): return "Integration unavailable: \(m)"
        case .exportFailed(let m): return "Export failed: \(m)"
        case .importFailed(let m): return "Import failed: \(m)"
        case .unsupported(let m): return "Unsupported: \(m)"
        }
    }
}
