import Foundation
import UserNotifications

/// Local notification delivery. Authorization is only requested when the user
/// enables notifications, never during initial launch.
public final class NotificationService {
    private let settingsRepository: SettingsRepository
    public private(set) var settings: UserSettings

    public init(database: Database) {
        self.settingsRepository = SettingsRepository(database: database)
        self.settings = (try? settingsRepository.load()) ?? .default
    }

    public func refreshSettings() {
        settings = (try? settingsRepository.load()) ?? settings
    }

    public func requestAuthorizationIfNeeded() {
        guard settings.notificationsEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { status in
            guard status.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    public func post(title: String, body: String, identifier: String = UUID().uuidString) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.debug("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Checks today's goals and streak and posts at most one notification.
    public func evaluateGoals(statistics: StatisticsService) {
        guard settings.notificationsEnabled else { return }
        let progress = statistics.goalProgress()
        for goal in progress {
            let id = "goal-\(goal.goal.id)-\(statistics.calendar.dayKey(for: Date()))"
            if goal.isComplete, goal.goal.period == .daily, settings.notifyOnGoals {
                post(
                    title: "Goal reached",
                    body: "You reached your \(goal.goal.metric.displayName.lowercased()) goal for today.",
                    identifier: id
                )
                return
            }
        }

        if settings.notifyOnStreaks {
            let streaks = statistics.streakStatistics()
            if streaks.currentStreak > 0 {
                let today = statistics.dailyStatistics(date: Date())
                if !today.isWritingDay, streaks.currentStreak >= 3 {
                    let id = "streak-risk-\(statistics.calendar.dayKey(for: Date()))"
                    post(
                        title: "Streak at risk",
                        body: "Your \(streaks.currentStreak)-day writing streak is waiting for today's words.",
                        identifier: id
                    )
                }
            }
        }
    }

    public func notifyMilestone(_ milestone: Milestone) {
        guard settings.notificationsEnabled, settings.notifyOnMilestones else { return }
        post(title: "Milestone complete", body: milestone.title, identifier: "milestone-\(milestone.id)")
    }
}
