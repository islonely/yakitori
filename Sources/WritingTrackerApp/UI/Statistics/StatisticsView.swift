import SwiftUI
import Charts
import WritingTrackerCore

struct StatisticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var range: DateRangeOption = .thisMonth

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader(title: "Statistics", subtitle: "Your writing output and patterns", symbol: "chart.bar.xaxis")
                summaryGrid
                dailyOutputChart
                HStack(alignment: .top, spacing: 16) {
                    activeTimeChart
                    timeOfDayChart
                }
                HStack(alignment: .top, spacing: 16) {
                    weekdayChart
                    durationChart
                }
                lifetimeSection
                patternsSection
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(DateRangeOption.allCases.filter { $0 != .custom && $0 != .allTime }) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }

    private var interval: DateInterval { range.interval(calendar: calendar) }
    private var days: [DailyStatistics] { statistics.dailyStatistics(from: interval.start, to: calendar.addingDays(-1, to: interval.end)) }
    private var period: PeriodStatistics { statistics.periodStatistics(start: interval.start, end: interval.end) }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            StatCard(title: "Net words", value: Format.int(period.netWords), subtitle: "manuscript change", systemImage: "text.word.spacing")
            StatCard(title: "Words added", value: Format.int(period.wordsAdded), subtitle: "estimated", systemImage: "plus")
            StatCard(title: "Words removed", value: Format.int(period.wordsRemoved), subtitle: "estimated", systemImage: "minus")
            StatCard(title: "Active time", value: Format.duration(period.activeSeconds), systemImage: "clock")
            StatCard(title: "Avg / day", value: Format.int(Int(period.averageWordsPerDay.rounded())), systemImage: "chart.line.uptrend.xyaxis")
            StatCard(title: "Avg / session", value: Format.int(Int(period.averageWordsPerSession.rounded())), systemImage: "rectangle.stack")
            StatCard(title: "Median / day", value: Format.int(medianDaily), systemImage: "equal")
            StatCard(title: "Best day", value: period.bestDay.map { Format.int($0.words) } ?? "—", systemImage: "star")
        }
    }

    private var medianDaily: Int {
        let values = days.map(\.netWords).sorted()
        guard !values.isEmpty else { return 0 }
        return values[values.count / 2]
    }

    private var dailyOutputChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily output", subtitle: range.title)
            Chart(days, id: \.dayKey) { day in
                BarMark(x: .value("Date", day.date, unit: .day), y: .value("Words", day.netWords))
                    .foregroundStyle(day.netWords >= 0 ? Theme.accent : Color.orange)
                    .cornerRadius(2)
            }
            .frame(height: 220)
        }
        .cardStyle()
    }

    private var activeTimeChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily active time", subtitle: "minutes")
            Chart(days, id: \.dayKey) { day in
                AreaMark(x: .value("Date", day.date, unit: .day), y: .value("Minutes", day.activeSeconds / 60))
                    .foregroundStyle(Theme.accent.opacity(0.25).gradient)
                LineMark(x: .value("Date", day.date, unit: .day), y: .value("Minutes", day.activeSeconds / 60))
                    .foregroundStyle(Theme.accent)
            }
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var timeOfDayChart: some View {
        let patterns = statistics.productivityPatterns()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Time of day", subtitle: "net words by hour (all time)")
            Chart(patterns.byHour, id: \.hour) { hour in
                BarMark(x: .value("Hour", hour.hour), y: .value("Words", hour.netWords))
                    .foregroundStyle(Theme.accent.gradient)
            }
            .frame(height: 200)
            if !patterns.hasSufficientData {
                Text("Not enough data yet for reliable patterns.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var weekdayChart: some View {
        let patterns = statistics.productivityPatterns()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Day of week", subtitle: "average words")
            Chart(patterns.byWeekday, id: \.weekday) { day in
                BarMark(x: .value("Weekday", weekdayName(day.weekday)), y: .value("Words", day.averageWords))
                    .foregroundStyle(Theme.accent.gradient)
            }
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var durationChart: some View {
        let sessions = (try? state.container.sessions.allSessions()) ?? []
        let buckets = durationBuckets(sessions)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Session length", subtitle: "number of sessions")
            Chart(buckets, id: \.label) { bucket in
                BarMark(x: .value("Length", bucket.label), y: .value("Sessions", bucket.count))
                    .foregroundStyle(Theme.accent.gradient)
            }
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var lifetimeSection: some View {
        let lifetime = statistics.lifetimeStatistics()
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Lifetime", subtitle: "your writing life")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Net words", value: Format.int(lifetime.lifetimeNetWords), systemImage: "text.word.spacing")
                MetricTile(title: "Writing days", value: Format.int(lifetime.writingDays), systemImage: "calendar")
                MetricTile(title: "Active hours", value: Format.decimal(lifetime.totalActiveSeconds / 3600), systemImage: "clock")
                MetricTile(title: "Sessions", value: Format.int(lifetime.totalSessions), systemImage: "rectangle.stack")
                MetricTile(title: "Projects", value: Format.int(lifetime.projectCount), systemImage: "books.vertical")
                MetricTile(title: "Completed", value: Format.int(lifetime.completedProjects), systemImage: "checkmark.seal")
                MetricTile(title: "Longest streak", value: "\(lifetime.longestStreak) days", systemImage: "flame")
                MetricTile(title: "Best WPM", value: lifetime.bestWordsPerMinute.map { Format.decimal($0) } ?? "—", systemImage: "speedometer")
            }
        }
        .cardStyle()
    }

    private var patternsSection: some View {
        let lifetime = statistics.lifetimeStatistics()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Highlights")
            if let bestDay = lifetime.bestDay {
                highlight("Best writing day", "\(Format.int(bestDay.words)) words on \(Format.shortDayYear.string(from: bestDay.date))")
            }
            if let bestSession = lifetime.bestSessionWords {
                highlight("Best session", "\(Format.int(bestSession)) net words")
            }
            if let year = lifetime.mostProductiveYear {
                highlight("Most productive year", year)
            }
            if let month = lifetime.mostProductiveMonth {
                highlight("Most productive month", month)
            }
            if let first = lifetime.firstTrackedDay {
                highlight("First tracked day", Format.shortDayYear.string(from: first))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func highlight(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.callout)
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = statistics.calendar.calendar.weekdaySymbols
        let index = weekday - 1
        guard index >= 0 && index < symbols.count else { return "?" }
        return String(symbols[index].prefix(3))
    }

    private func durationBuckets(_ sessions: [Session]) -> [(label: String, count: Int)] {
        var buckets = [("<15m", 0), ("15–30m", 0), ("30–60m", 0), ("1–2h", 0), ("2h+", 0)]
        for session in sessions {
            let minutes = session.activeSeconds / 60
            switch minutes {
            case ..<15: buckets[0].1 += 1
            case ..<30: buckets[1].1 += 1
            case ..<60: buckets[2].1 += 1
            case ..<120: buckets[3].1 += 1
            default: buckets[4].1 += 1
            }
        }
        return buckets.map { (label: $0.0, count: $0.1) }
    }
}
