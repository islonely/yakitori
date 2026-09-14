import Foundation

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// A user-configurable global keyboard shortcut.
public struct HotkeyConfiguration: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    /// Carbon modifier mask (cmdKey | optionKey | controlKey | shiftKey).
    public var carbonModifiers: UInt32
    /// Human-readable form, e.g. "⌃⌥⌘S". Stored for display only.
    public var display: String
    public var enabled: Bool

    public init(keyCode: UInt16, carbonModifiers: UInt32, display: String, enabled: Bool = true) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
        self.enabled = enabled
    }

    // Carbon modifier values (see Carbon/HIToolbox/Events.h).
    public static let modifierCommand: UInt32 = 256
    public static let modifierShift: UInt32 = 512
    public static let modifierOption: UInt32 = 2048
    public static let modifierControl: UInt32 = 4096
}

/// Persisted user configuration. Stored as a single JSON document.
public struct UserSettings: Codable, Hashable, Sendable {
    public var trackingMode: TrackingMode
    public var selectedApplicationIDs: [String]
    public var inactivityTimeout: InactivityTimeout
    public var defaultSessionType: SessionType
    public var streakThresholdKind: StreakThresholdKind
    public var streakCustomWords: Int
    public var notificationsEnabled: Bool
    public var notifyOnGoals: Bool
    public var notifyOnStreaks: Bool
    public var notifyOnMilestones: Bool
    public var writingSchedule: [WritingSchedule]
    public var weekStart: WeekStart
    public var launchAtLogin: Bool
    public var startTrackingAtLaunch: Bool
    public var onboardingCompleted: Bool
    public var currentProjectID: String?
    public var diagnosticsEnabled: Bool
    public var menuBarShowsWordCount: Bool
    public var appearance: AppAppearance
    public var automaticProjectMatching: Bool
    /// Global shortcut to start/stop a session. Nil means disabled.
    public var globalHotkey: HotkeyConfiguration?
    /// Community: name shown on leaderboards.
    public var communityDisplayName: String?
    /// Community: opt-in to publishing aggregate stats.
    public var publishStatsEnabled: Bool
    /// Community: show clearly-labelled sample entries (placeholder for the server).
    public var showSampleCommunity: Bool
    public var schemaVersion: Int

    public init(
        trackingMode: TrackingMode = .automaticFiltered,
        selectedApplicationIDs: [String] = [],
        inactivityTimeout: InactivityTimeout = .default,
        defaultSessionType: SessionType = .drafting,
        streakThresholdKind: StreakThresholdKind = .anyWriting,
        streakCustomWords: Int = 250,
        notificationsEnabled: Bool = false,
        notifyOnGoals: Bool = true,
        notifyOnStreaks: Bool = true,
        notifyOnMilestones: Bool = true,
        writingSchedule: [WritingSchedule] = WritingSchedule.defaultWeek(),
        weekStart: WeekStart = .sunday,
        launchAtLogin: Bool = false,
        startTrackingAtLaunch: Bool = true,
        onboardingCompleted: Bool = false,
        currentProjectID: String? = nil,
        diagnosticsEnabled: Bool = false,
        menuBarShowsWordCount: Bool = true,
        appearance: AppAppearance = .system,
        automaticProjectMatching: Bool = true,
        globalHotkey: HotkeyConfiguration? = nil,
        communityDisplayName: String? = nil,
        publishStatsEnabled: Bool = false,
        showSampleCommunity: Bool = false,
        schemaVersion: Int = 1
    ) {
        self.trackingMode = trackingMode
        self.selectedApplicationIDs = selectedApplicationIDs
        self.inactivityTimeout = inactivityTimeout
        self.defaultSessionType = defaultSessionType
        self.streakThresholdKind = streakThresholdKind
        self.streakCustomWords = streakCustomWords
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnGoals = notifyOnGoals
        self.notifyOnStreaks = notifyOnStreaks
        self.notifyOnMilestones = notifyOnMilestones
        self.writingSchedule = writingSchedule
        self.weekStart = weekStart
        self.launchAtLogin = launchAtLogin
        self.startTrackingAtLaunch = startTrackingAtLaunch
        self.onboardingCompleted = onboardingCompleted
        self.currentProjectID = currentProjectID
        self.diagnosticsEnabled = diagnosticsEnabled
        self.menuBarShowsWordCount = menuBarShowsWordCount
        self.appearance = appearance
        self.automaticProjectMatching = automaticProjectMatching
        self.globalHotkey = globalHotkey
        self.communityDisplayName = communityDisplayName
        self.publishStatsEnabled = publishStatsEnabled
        self.showSampleCommunity = showSampleCommunity
        self.schemaVersion = schemaVersion
    }

    public var streakThresholdWords: Int {
        switch streakThresholdKind {
        case .anyWriting: return 0
        case .words100: return 100
        case .words250: return 250
        case .words500: return 500
        case .custom: return max(0, streakCustomWords)
        }
    }

    public func isScheduledDay(weekday: Int) -> Bool {
        writingSchedule.first(where: { $0.weekday == weekday })?.enabled ?? false
    }

    public static let `default` = UserSettings()
}

// MARK: - Monetization architecture (no enforcement in v1)

public enum Entitlement: String, Codable, CaseIterable, Sendable {
    case free
    case pro
    case cloud
}

public enum Feature: String, Codable, CaseIterable, Sendable {
    case localTracking
    case basicDashboard
    case basicStatistics
    case unlimitedProjects
    case lifetimeAnalytics
    case advancedCharts
    case advancedIntegrations
    case reports
    case advancedProductivityAnalysis
    case historicalComparisons
    case advancedGoals
    case dataExports
    case cloudSync
    case cloudBackup

    public static let freeFeatures: Set<Feature> = [
        .localTracking, .basicDashboard, .basicStatistics, .dataExports
    ]

    public static let proFeatures: Set<Feature> = [
        .unlimitedProjects, .lifetimeAnalytics, .advancedCharts, .advancedIntegrations,
        .reports, .advancedProductivityAnalysis, .historicalComparisons, .advancedGoals
    ]

    public static let cloudFeatures: Set<Feature> = [
        .cloudSync, .cloudBackup
    ]
}

/// Per-feature tiers kept for future monetization (for example cloud features).
/// It is **not** the active entitlement gate: enforcement today is time-based
/// (a 14-day trial or a lifetime license) and lives in `LicensingService` /
/// `TrackingEngine.setTrackingAllowed`.
public final class FeatureFlags: @unchecked Sendable {
    public static let shared = FeatureFlags()

    private let lock = NSLock()
    private var entitlement: Entitlement

    public init(entitlement: Entitlement = .pro) {
        self.entitlement = entitlement
    }

    public var currentEntitlement: Entitlement {
        lock.lock(); defer { lock.unlock() }
        return entitlement
    }

    public func setEntitlement(_ value: Entitlement) {
        lock.lock(); defer { lock.unlock() }
        entitlement = value
    }

    public func isEnabled(_ feature: Feature) -> Bool {
        switch currentEntitlement {
        case .cloud:
            return true
        case .pro:
            return !Feature.cloudFeatures.contains(feature)
        case .free:
            return Feature.freeFeatures.contains(feature)
        }
    }
}

public enum FreeTierLimits {
    public static let maxProjects = 3
}
