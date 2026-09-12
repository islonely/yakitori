import Foundation

// MARK: - Project

public enum ProjectType: String, Codable, CaseIterable, Identifiable, Sendable {
    case novel
    case novella
    case shortStory
    case collection
    case screenplay
    case nonfiction
    case article
    case academic
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .novel: return "Novel"
        case .novella: return "Novella"
        case .shortStory: return "Short Story"
        case .collection: return "Collection"
        case .screenplay: return "Screenplay"
        case .nonfiction: return "Nonfiction"
        case .article: return "Article"
        case .academic: return "Academic"
        case .other: return "Other"
        }
    }
}

public enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case idea
    case planning
    case drafting
    case revising
    case editing
    case proofreading
    case complete
    case published
    case abandoned
    case archived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Planning"
        case .drafting: return "Drafting"
        case .revising: return "Revising"
        case .editing: return "Editing"
        case .proofreading: return "Proofreading"
        case .complete: return "Complete"
        case .published: return "Published"
        case .abandoned: return "Abandoned"
        case .archived: return "Archived"
        }
    }

    /// A project is considered "active" unless it is complete, published, abandoned or archived.
    public var isActive: Bool {
        switch self {
        case .complete, .published, .abandoned, .archived: return false
        default: return true
        }
    }

    public var isCompleted: Bool {
        switch self {
        case .complete, .published: return true
        default: return false
        }
    }
}

// MARK: - Sessions

public enum SessionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case drafting
    case editing
    case revising
    case proofreading
    case research
    case planning
    case other
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .drafting: return "Drafting"
        case .editing: return "Editing"
        case .revising: return "Revising"
        case .proofreading: return "Proofreading"
        case .research: return "Research"
        case .planning: return "Planning"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Activity events

public enum ActivityEventType: String, Codable, CaseIterable, Sendable {
    case applicationFocused
    case applicationUnfocused
    case keyboardActivity
    case mouseActivity
    case documentChanged
    case wordCountSampled
    case sessionStarted
    case sessionPaused
    case sessionResumed
    case sessionEnded
    case systemSleep
    case systemWake

    public var displayName: String {
        switch self {
        case .applicationFocused: return "Application Focused"
        case .applicationUnfocused: return "Application Unfocused"
        case .keyboardActivity: return "Keyboard Activity"
        case .mouseActivity: return "Mouse Activity"
        case .documentChanged: return "Document Changed"
        case .wordCountSampled: return "Word Count Sampled"
        case .sessionStarted: return "Session Started"
        case .sessionPaused: return "Session Paused"
        case .sessionResumed: return "Session Resumed"
        case .sessionEnded: return "Session Ended"
        case .systemSleep: return "System Sleep"
        case .systemWake: return "System Wake"
        }
    }
}

// MARK: - Tracking

public enum TrackingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case automatic
    case automaticFiltered

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        case .automaticFiltered: return "Automatic (selected applications only)"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        case .automaticFiltered: return "Automatic (selected apps)"
        }
    }
}

public enum InactivityTimeout: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900

    public var id: Int { rawValue }

    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var displayName: String {
        switch self {
        case .never: return "Never"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .fifteenMinutes: return "15 minutes"
        }
    }

    public static let `default`: InactivityTimeout = .fiveMinutes
}

// MARK: - Goals

public enum GoalPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case project
    case deadline

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .project: return "Project"
        case .deadline: return "Deadline"
        }
    }
}

public enum GoalMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case words
    case activeMinutes
    case sessions

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .words: return "Words"
        case .activeMinutes: return "Active Minutes"
        case .sessions: return "Sessions"
        }
    }

    public var unit: String {
        switch self {
        case .words: return "words"
        case .activeMinutes: return "min"
        case .sessions: return "sessions"
        }
    }
}

// MARK: - Streaks

public enum StreakThresholdKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anyWriting
    case words100
    case words250
    case words500
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anyWriting: return "Any writing activity"
        case .words100: return "100 words"
        case .words250: return "250 words"
        case .words500: return "500 words"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Calendar

public enum WeekStart: String, Codable, CaseIterable, Identifiable, Sendable {
    case sunday
    case monday

    public var id: String { rawValue }

    public var displayName: String { self == .sunday ? "Sunday" : "Monday" }

    public var firstWeekday: Int { self == .sunday ? 1 : 2 }
}

// MARK: - Applications

public enum ApplicationCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case writing
    case research
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .writing: return "Writing"
        case .research: return "Research"
        case .other: return "Other"
        }
    }
}

public enum AdapterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case word
    case scrivener
    case pages
    case ulysses
    case browser
    case libreOffice
    case obsidian
    case generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .word: return "Microsoft Word"
        case .scrivener: return "Scrivener"
        case .pages: return "Pages"
        case .ulysses: return "Ulysses"
        case .browser: return "Browser"
        case .libreOffice: return "LibreOffice"
        case .obsidian: return "Obsidian"
        case .generic: return "Generic"
        }
    }
}

// MARK: - Permissions

public enum PermissionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case accessibility
    case wordAutomation
    case fileAccess
    case notifications
    case launchAtLogin

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .wordAutomation: return "Document Automation (Word, Pages)"
        case .fileAccess: return "Selected File Access"
        case .notifications: return "Notifications"
        case .launchAtLogin: return "Launch at Login"
        }
    }
}

public enum PermissionState: String, Codable, CaseIterable, Sendable {
    case granted
    case denied
    case notDetermined
    case notApplicable

    public var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not Granted"
        case .notDetermined: return "Not Requested"
        case .notApplicable: return "Not Applicable"
        }
    }
}
