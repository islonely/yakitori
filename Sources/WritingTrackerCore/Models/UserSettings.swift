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

/// Central feature gate. The local product ships with everything unlocked;
/// this exists so monetization can be added later without touching views.
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
