import Foundation

/// Builds per-day aggregates from raw sessions.
///
/// Sessions (and their exact active/focus ranges) remain the source of truth;
/// aggregates are a derived cache that can always be rebuilt.
public struct DailyAggregateBuilder {
    public let calendar: CalendarContext

    public init(calendar: CalendarContext = CalendarContext()) {
        self.calendar = calendar
    }

    public func aggregates(for sessions: [Session]) -> [DailyAggregate] {
        var buckets: [String: MutableAggregate] = [:]

        for session in sessions {
            // Ignore zero-activity artifacts (e.g. sessions recovered after a crash).
            let hasActivity = session.activeSeconds > 0
                || session.focusSeconds > 0
                || (session.netWordChange ?? 0) != 0
                || !session.activeRanges.isEmpty
                || !session.focusRanges.isEmpty
            guard hasActivity else { continue }

            let sessionEnd = session.endedAt ?? session.startedAt
            let days = Set(
                calendar.days(from: session.startedAt, through: sessionEnd).map { calendar.dayKey(for: $0) }
            )

            for dayKey in days {
                guard let dayStart = calendar.date(fromDayKey: dayKey) else { continue }
                let dayEnd = calendar.endOfDay(for: dayStart)
                var bucket = buckets[dayKey] ?? MutableAggregate(dayKey: dayKey, date: dayStart)

                if let added = session.wordsAdded, let removed = session.wordsRemoved {
                    // Edit-level detail is available.
                    bucket.wordsAdded += added
                    bucket.wordsRemoved += removed
                    bucket.netWords += session.netWordChange ?? (added - removed)
                } else if let net = session.netWordChange {
                    if net >= 0 {
                        bucket.wordsAdded += net
                    } else {
                        bucket.wordsRemoved += -net
                    }
                    bucket.netWords += net
                } else if let start = session.startingWordCount, let end = session.endingWordCount {
                    let net = end - start
                    if net >= 0 { bucket.wordsAdded += net } else { bucket.wordsRemoved += -net }
                    bucket.netWords += net
                }

                let activeSeconds = session.activeRanges.isEmpty
                    ? syntheticSeconds(session.activeSeconds, startedAt: session.startedAt, endedAt: session.endedAt, dayStart: dayStart, dayEnd: dayEnd)
                    : overlapSeconds(session.activeRanges, dayStart: dayStart, dayEnd: dayEnd)
                let focusSeconds = session.focusRanges.isEmpty
                    ? syntheticSeconds(session.focusSeconds, startedAt: session.startedAt, endedAt: session.endedAt, dayStart: dayStart, dayEnd: dayEnd)
                    : overlapSeconds(session.focusRanges, dayStart: dayStart, dayEnd: dayEnd)

                bucket.activeSeconds += activeSeconds
                bucket.focusSeconds += focusSeconds
                bucket.projectIDs.insert(session.projectID)
                // A session that spans midnight contributes to each day it overlaps.
                bucket.sessionCount += 1
                let sessionStart = session.startedAt
                if bucket.firstSessionAt == nil || sessionStart < bucket.firstSessionAt! {
                    bucket.firstSessionAt = sessionStart
                }
                if bucket.lastSessionAt == nil || sessionEnd > bucket.lastSessionAt! {
                    bucket.lastSessionAt = sessionEnd
                }
                buckets[dayKey] = bucket
            }
        }

        return buckets.values
            .map { $0.finalized() }
            .sorted { $0.date < $1.date }
    }

    public func aggregate(for sessions: [Session], on day: Date) -> DailyAggregate {
        let dayKey = calendar.dayKey(for: day)
        return aggregates(for: sessions).first { $0.dayKey == dayKey }
            ?? DailyAggregate(dayKey: dayKey, date: calendar.startOfDay(for: day))
    }

    private func overlapSeconds(_ ranges: [TimeRange], dayStart: Date, dayEnd: Date) -> Double {
        ranges.reduce(0) { total, range in
            let start = max(range.start, dayStart)
            let end = min(range.end, dayEnd)
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// Best-effort distribution for legacy/manual rows that lack exact ranges.
    private func syntheticSeconds(
        _ total: Double,
        startedAt: Date,
        endedAt: Date?,
        dayStart: Date,
        dayEnd: Date
    ) -> Double {
        guard total > 0 else { return 0 }
        let spanEnd = endedAt ?? startedAt.addingTimeInterval(total)
        let start = max(startedAt, dayStart)
        let end = min(spanEnd, dayEnd)
        guard end > start else { return 0 }
        let overlap = end.timeIntervalSince(start)
        let span = max(total, spanEnd.timeIntervalSince(startedAt))
        guard span > 0 else { return 0 }
        return total * (overlap / span)
    }

    private struct MutableAggregate {
        let dayKey: String
        let date: Date
        var wordsAdded = 0
        var wordsRemoved = 0
        var netWords = 0
        var activeSeconds: Double = 0
        var focusSeconds: Double = 0
        var sessionCount = 0
        var projectIDs: Set<String?> = []
        var firstSessionAt: Date?
        var lastSessionAt: Date?

        func finalized() -> DailyAggregate {
            DailyAggregate(
                dayKey: dayKey,
                date: date,
                wordsAdded: wordsAdded,
                wordsRemoved: wordsRemoved,
                netWords: netWords,
                activeSeconds: activeSeconds,
                focusSeconds: focusSeconds,
                sessionCount: sessionCount,
                projectCount: projectIDs.compactMap { $0 }.count,
                firstSessionAt: firstSessionAt,
                lastSessionAt: lastSessionAt
            )
        }
    }
}
