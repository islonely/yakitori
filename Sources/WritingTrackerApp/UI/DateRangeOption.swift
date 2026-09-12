import Foundation
import WritingTrackerCore

enum DateRangeOption: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear
    case allTime
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .lastWeek: return "Last week"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .thisYear: return "This year"
        case .lastYear: return "Last year"
        case .allTime: return "All time"
        case .custom: return "Custom"
        }
    }

    /// The granularity used for charts.
    var isSingleDay: Bool { self == .today || self == .yesterday }

    func interval(calendar: CalendarContext, customStart: Date? = nil, customEnd: Date? = nil) -> DateInterval {
        let now = Date()
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: calendar.addingDays(1, to: start))
        case .yesterday:
            let start = calendar.addingDays(-1, to: calendar.startOfDay(for: now))
            return DateInterval(start: start, end: calendar.addingDays(1, to: start))
        case .thisWeek:
            let start = calendar.startOfWeek(for: now)
            return DateInterval(start: start, end: calendar.addingDays(7, to: start))
        case .lastWeek:
            let start = calendar.addingDays(-7, to: calendar.startOfWeek(for: now))
            return DateInterval(start: start, end: calendar.addingDays(7, to: start))
        case .thisMonth:
            let start = calendar.startOfMonth(for: now)
            return DateInterval(start: start, end: calendar.calendar.date(byAdding: .month, value: 1, to: start) ?? calendar.addingDays(31, to: start))
        case .lastMonth:
            let thisMonth = calendar.startOfMonth(for: now)
            let start = calendar.calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? calendar.addingDays(-30, to: thisMonth)
            return DateInterval(start: start, end: thisMonth)
        case .thisYear:
            let start = calendar.startOfYear(for: now)
            return DateInterval(start: start, end: calendar.calendar.date(byAdding: .year, value: 1, to: start) ?? calendar.addingDays(365, to: start))
        case .lastYear:
            let thisYear = calendar.startOfYear(for: now)
            let start = calendar.calendar.date(byAdding: .year, value: -1, to: thisYear) ?? calendar.addingDays(-365, to: thisYear)
            return DateInterval(start: start, end: thisYear)
        case .allTime:
            return DateInterval(start: .distantPast, end: calendar.addingDays(1, to: calendar.startOfDay(for: now)))
        case .custom:
            let start = calendar.startOfDay(for: customStart ?? now)
            let end = calendar.endOfDay(for: customEnd ?? now)
            return DateInterval(start: start, end: end)
        }
    }
}
