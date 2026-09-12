import Foundation

/// Abstraction over "now" so time-dependent logic can be tested deterministically.
public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

/// Mutable provider used by tests and previews.
public final class MutableDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(_ now: Date = Date()) {
        self._now = now
    }

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }

    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }
}

/// Timezone- and DST-aware calendar helper.
///
/// All timestamps are stored as absolute `Date` values. Day boundaries and
/// aggregate keys are always derived through this type so that midnight,
/// DST transitions and timezone changes are handled correctly.
public struct CalendarContext: Hashable, Sendable {
    public var calendar: Calendar

    public init(
        timeZone: TimeZone = .current,
        firstWeekday: WeekStart = .sunday,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = firstWeekday.firstWeekday
        cal.locale = locale
        cal.minimumDaysInFirstWeek = 1
        self.calendar = cal
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }

    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Stable `yyyy-MM-dd` key for the local day containing `date`.
    public func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }

    public func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    public func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }

    public func startOfYear(for date: Date) -> Date {
        calendar.dateInterval(of: .year, for: date)?.start ?? startOfDay(for: date)
    }

    public func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Days between two day-starts, accounting for DST (not a naive 24h division).
    public func daysBetween(_ start: Date, _ end: Date) -> Int {
        let a = startOfDay(for: start)
        let b = startOfDay(for: end)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public func daysInMonth(for date: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let start = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public func hour(of date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    public func weekday(of date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Enumerates day-start dates from `start` through `end` (inclusive).
    public func days(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = startOfDay(for: start)
        let last = startOfDay(for: end)
        var safety = 0
        while cursor <= last && safety < 200_000 {
            safety += 1
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }

    /// ISO-week style key for a date, e.g. `2026-W37`.
    public func weekKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    public func monthKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    public func yearKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year], from: date)
        return String(format: "%04d", comps.year ?? 0)
    }
}

public enum DurationFormatter {
    /// "1h 17m", "42m", "18s"
    public static func short(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        } else if total >= 60 {
            let m = total / 60
            return "\(m)m"
        } else {
            return "\(total)s"
        }
    }
}
