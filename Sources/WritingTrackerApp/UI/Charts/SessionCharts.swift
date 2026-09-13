import SwiftUI
import Charts
import WritingTrackerCore

/// Active minutes vs net words, one dot per session, coloured by session type.
struct SessionScatterChart: View {
    let points: [SessionPoint]
    var height: CGFloat = 240

    var body: some View {
        Chart(points) { point in
            PointMark(
                x: .value("Active minutes", point.activeMinutes),
                y: .value("Net words", point.netWords)
            )
            .foregroundStyle(by: .value("Type", point.sessionType.displayName))
            .symbolSize(38)
        }
        .frame(height: height)
        .chartForegroundStyleScale(domain: ChartStyle.sessionTypeDomain, range: ChartStyle.sessionTypeRange)
        .chartXAxisLabel("Active minutes")
        .chartYAxisLabel("Net words")
    }
}

/// Typing pace over time.
struct PaceTrendChart: View {
    let points: [PacePoint]
    var height: CGFloat = 220

    var body: some View {
        Chart(points) { point in
            PointMark(x: .value("Date", point.date, unit: .day), y: .value("WPM", point.pace))
                .foregroundStyle(Theme.ember.opacity(0.5))
                .symbolSize(18)
            LineMark(x: .value("Date", point.date, unit: .day), y: .value("WPM", point.pace))
                .foregroundStyle(Theme.ember)
        }
        .frame(height: height)
        .chartYAxisLabel("words / minute")
    }
}

/// Distribution of typing pace across sessions.
struct PaceHistogramChart: View {
    let points: [PacePoint]
    var height: CGFloat = 200

    private struct Bucket: Identifiable {
        var id: Int { lower }
        let lower: Int
        let count: Int
    }

    private var buckets: [Bucket] {
        guard !points.isEmpty else { return [] }
        let grouped = Dictionary(grouping: points) { Int($0.pace / 10.0) * 10 }
        return grouped.map { Bucket(lower: $0.key, count: $0.value.count) }.sorted { $0.lower < $1.lower }
    }

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("WPM", bucket.lower), y: .value("Sessions", bucket.count))
                .foregroundStyle(Theme.ember.gradient)
        }
        .frame(height: height)
        .chartXAxisLabel("words / minute")
    }
}

/// Words per day, stacked by session type.
struct SessionTypeStackChart: View {
    let days: [SessionTypeDay]
    var height: CGFloat = 220

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Date", day.date, unit: .day), y: .value("Words", day.words))
                .foregroundStyle(by: .value("Type", day.type.displayName))
        }
        .frame(height: height)
        .chartForegroundStyleScale(domain: ChartStyle.sessionTypeDomain, range: ChartStyle.sessionTypeRange)
    }
}

/// Each streak as a bar.
struct StreakLadderChart: View {
    let runs: [StreakRun]
    var height: CGFloat = 180

    var body: some View {
        Chart(runs) { run in
            BarMark(x: .value("Streak", run.start, unit: .day), y: .value("Days", run.length))
                .foregroundStyle(run.isCurrent ? Theme.ember : Theme.gold.opacity(0.7))
        }
        .frame(height: height)
        .chartYAxisLabel("days")
    }
}

/// Added vs removed words per day (diverging).
struct AddedRemovedChart: View {
    let points: [AddedRemovedPoint]
    var height: CGFloat = 200

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Date", point.date, unit: .day), y: .value("Added", point.added))
                    .foregroundStyle(Theme.ember)
                BarMark(x: .value("Date", point.date, unit: .day), y: .value("Removed", -point.removed))
                    .foregroundStyle(Theme.gold)
            }
        }
        .frame(height: height)
        .chartForegroundStyleScale(["Added": Theme.ember, "Removed": Theme.gold])
    }
}

/// Personal-record callouts.
struct RecordsStrip: View {
    let lifetime: LifetimeStatistics
    let bestWeek: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            record("Best day", lifetime.bestDay.map { "\(Format.int($0.words))" } ?? "—", "star.fill")
            record("Best session", lifetime.bestSessionWords.map { Format.int($0) } ?? "—", "bolt.fill")
            record("Best pace", lifetime.bestWordsPerMinute.map { "\(Format.decimal($0)) wpm" } ?? "—", "speedometer")
            record("Best week", Format.int(bestWeek), "calendar")
            record("Longest streak", "\(lifetime.longestStreak) days", "flame.fill")
            record("Best day ever", lifetime.bestDay.map { Format.shortDay.string(from: $0.date) } ?? "—", "trophy.fill")
        }
    }

    private func record(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption).foregroundStyle(Theme.accent)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.ember.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
