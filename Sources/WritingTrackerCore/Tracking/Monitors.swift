import Foundation
import AppKit
import CoreGraphics

/// Observes the globally frontmost application.
public final class FrontmostApplicationMonitor {
    public var onFrontmostChanged: ((FrontmostApplicationInfo) -> Void)?
    private var observer: NSObjectProtocol?
    private var isRunning = false

    public init() {}

    public var current: FrontmostApplicationInfo? {
        Self.info(from: NSWorkspace.shared.frontmostApplication)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard let info = Self.info(from: app) else { return }
            self?.onFrontmostChanged?(info)
        }
        if let info = current {
            onFrontmostChanged?(info)
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        isRunning = false
    }

    static func info(from application: NSRunningApplication?) -> FrontmostApplicationInfo? {
        guard let application else { return nil }
        return FrontmostApplicationInfo(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName ?? application.bundleIdentifier ?? "Unknown",
            processIdentifier: application.processIdentifier
        )
    }
}

/// Inactivity signal provider based on CoreGraphics' system idle counter.
/// Works without any permission, including Accessibility.
public protocol SystemIdleProviding {
    /// Seconds since the last user input event.
    func secondsSinceLastInput() -> TimeInterval
}

public struct CGSystemIdleProvider: SystemIdleProviding {
    public init() {}
    public func secondsSinceLastInput() -> TimeInterval {
        let anyEvent = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }
}

/// Observes system sleep/wake and screen lock events.
public final class SystemSleepMonitor {
    public var onWillSleep: ((Date) -> Void)?
    public var onDidWake: ((Date) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onWillSleep?(Date())
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDidWake?(Date())
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onWillSleep?(Date())
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDidWake?(Date())
        })
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        isRunning = false
    }
}

/// Local time-change observer (timezone / clock changes).
public final class TimeChangeMonitor {
    public var onTimeChanged: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.onTimeChanged?()
        })
        observers.append(center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.onTimeChanged?()
        })
    }

    public func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}
