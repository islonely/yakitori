import Foundation
import AppKit
import ApplicationServices
import UserNotifications
import ServiceManagement

public struct PermissionStatus: Equatable, Sendable {
    public var kind: PermissionKind
    public var state: PermissionState
    public var detail: String?

    public init(kind: PermissionKind, state: PermissionState, detail: String? = nil) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }
}

/// Describes which permissions a capability depends on.
public struct PermissionRequirement: Identifiable, Hashable, Sendable {
    public var id: String { capability }
    public let capability: String
    public let required: [PermissionKind]
    public let degradedExplanation: String

    public init(capability: String, required: [PermissionKind], degradedExplanation: String) {
        self.capability = capability
        self.required = required
        self.degradedExplanation = degradedExplanation
    }

    public static let automaticActivityTracking = PermissionRequirement(
        capability: "Automatic activity tracking",
        required: [.accessibility],
        degradedExplanation: "Without Accessibility, the tracker cannot detect keyboard activity and will only record focus time."
    )

    public static let wordWordCount = PermissionRequirement(
        capability: "Microsoft Word word counts",
        required: [.wordAutomation],
        degradedExplanation: "Without Automation permission, Word word counts are unavailable; focus and activity tracking continue."
    )

    public static let directFileAccess = PermissionRequirement(
        capability: "Direct file access",
        required: [.fileAccess],
        degradedExplanation: "Without file access the tracker cannot read the selected file or folder directly."
    )

    public static let notifications = PermissionRequirement(
        capability: "Notifications",
        required: [.notifications],
        degradedExplanation: "Without Notifications, goal and streak alerts cannot be delivered."
    )

    public static let launchAtLogin = PermissionRequirement(
        capability: "Launch at Login",
        required: [.launchAtLogin],
        degradedExplanation: "Launch at Login could not be enabled; start the app manually after restarting."
    )
}

public protocol PermissionProviding: AnyObject {
    var onChange: (() -> Void)? { get set }
    func status(for kind: PermissionKind) -> PermissionStatus
    func allStatuses() -> [PermissionStatus]
    func request(_ kind: PermissionKind)
    func openSystemSettings(for kind: PermissionKind)
    func setLaunchAtLogin(_ enabled: Bool)
    func refresh()
}

public extension PermissionProviding {
    func allStatuses() -> [PermissionStatus] {
        PermissionKind.allCases.map { status(for: $0) }
    }
}

/// Real macOS permission manager. Permission-dependent features degrade
/// gracefully when a permission is unavailable; nothing is bypassed.
public final class PermissionManager: PermissionProviding {
    public var onChange: (() -> Void)?

    private var wordAutomationState: PermissionState = .notDetermined
    private var notificationState: PermissionState = .notDetermined
    private var fileAccessState: PermissionState = .notApplicable
    private var launchAtLoginState: PermissionState = .notDetermined

    public init() {
        refresh()
    }

    public func refresh() {
        notificationState = cachedNotificationState
        launchAtLoginState = currentLaunchAtLoginState
        fileAccessState = FileAccessBookmarkStore.shared.hasAnyBookmark ? .granted : .notApplicable
    }

    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            let trusted = AXIsProcessTrusted()
            return PermissionStatus(
                kind: kind,
                state: trusted ? .granted : .denied,
                detail: trusted ? nil : "Keyboard activity detection is limited."
            )
        case .wordAutomation:
            return PermissionStatus(kind: kind, state: wordAutomationState,
                                    detail: wordAutomationState == .denied ? "Microsoft Word word counts unavailable." : nil)
        case .fileAccess:
            return PermissionStatus(kind: kind, state: fileAccessState,
                                    detail: fileAccessState == .notApplicable ? "No file or folder selected yet." : nil)
        case .notifications:
            return PermissionStatus(kind: kind, state: notificationState)
        case .launchAtLogin:
            return PermissionStatus(kind: kind, state: launchAtLoginState)
        }
    }

    public func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .wordAutomation:
            requestWordAutomation()
        case .fileAccess:
            // File access is requested through NSOpenPanel when the user selects a file.
            break
        case .notifications:
            requestNotifications()
        case .launchAtLogin:
            setLaunchAtLogin(true)
        }
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    /// Runs a harmless Word query to trigger the Automation prompt.
    public func requestWordAutomation() {
        guard ApplicationLocator.isRunning(bundleIdentifier: "com.microsoft.Word") else {
            wordAutomationState = .notDetermined
            return
        }
        do {
            _ = try AppleScriptExecutor().execute("tell application \"Microsoft Word\" to get version")
            wordAutomationState = .granted
        } catch ScriptError.permissionDenied {
            wordAutomationState = .denied
        } catch {
            // Word may be busy; keep the last known state rather than guessing.
        }
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    /// Called by the Word adapter so automation state reflects reality.
    public func updateWordAutomation(granted: Bool) {
        let newState: PermissionState = granted ? .granted : .denied
        if newState != wordAutomationState {
            wordAutomationState = newState
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    public func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            self.notificationState = granted ? .granted : .denied
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.permissions.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLoginState = currentLaunchAtLoginState
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        let urlString: String?
        switch kind {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .wordAutomation:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .fileAccess:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .launchAtLogin:
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        }
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var currentLaunchAtLoginState: PermissionState {
        switch SMAppService.mainApp.status {
        case .enabled: return .granted
        case .notRegistered, .notFound: return .notApplicable
        case .requiresApproval: return .denied
        @unknown default: return .notDetermined
        }
    }

    private var cachedNotificationState: PermissionState {
        // Synchronous best-effort; async refresh updates the cache.
        var state: PermissionState = .notDetermined
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .notDetermined
            @unknown default: state = .notDetermined
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return state
    }
}

/// Test/preview double.
public final class MockPermissionManager: PermissionProviding {
    public var onChange: (() -> Void)?
    private var states: [PermissionKind: PermissionState]

    public init(states: [PermissionKind: PermissionState] = [:]) {
        self.states = states
    }

    public func set(_ state: PermissionState, for kind: PermissionKind) {
        states[kind] = state
        onChange?()
    }

    public func status(for kind: PermissionKind) -> PermissionStatus {
        PermissionStatus(kind: kind, state: states[kind] ?? .notDetermined)
    }

    public func request(_ kind: PermissionKind) {
        states[kind] = .granted
        onChange?()
    }

    public func openSystemSettings(for kind: PermissionKind) {}
    public func setLaunchAtLogin(_ enabled: Bool) {}
    public func refresh() {}
}
