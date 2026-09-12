import SwiftUI
import WritingTrackerCore

enum HeatmapMetric: String, CaseIterable, Identifiable {
    case words
    case activeMinutes
    case sessions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .words: return "Words"
        case .activeMinutes: return "Active Minutes"
        case .sessions: return "Sessions"
        }
    }

    func value(_ stat: DailyStatistics) -> Double {
        switch self {
        case .words: return Double(stat.netWords)
        case .activeMinutes: return stat.activeSeconds / 60
        case .sessions: return Double(stat.sessionCount)
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject private var state: AppState
    @State private var metric: HeatmapMetric = .words
    @State private var selectedDay: DailyStatistics?

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    private var days: [DailyStatistics] {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.addingDays(-370, to: end)
        return statistics.dailyStatistics(from: start, to: end)
    }

    private var byKey: [String: DailyStatistics] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.dayKey, $0) })
    }

    private var maxValue: Double {
        max(1, days.map { max(0, metric.value($0)) }.max() ?? 1)
    }

    private var weeks: [[Date]] {
        guard let first = days.first?.date, let last = days.last?.date else { return [] }
        let gridStart = calendar.startOfWeek(for: first)
        var result: [[Date]] = []
        var current: [Date] = []
        for day in calendar.days(from: gridStart, through: last) {
            current.append(day)
            if current.count == 7 {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Calendar").font(.largeTitle.weight(.semibold))
                    Spacer()
                    Picker("Metric", selection: $metric) {
                        ForEach(HeatmapMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                heatmap
                legend
                if let selectedDay {
                    dailyDetail(selectedDay)
                } else {
                    Text("Click a day to see its details.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Calendar")
    }

    private var heatmap: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 3) {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdayLabel(index))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(height: 13, alignment: .center)
                            .frame(width: 24, alignment: .trailing)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(week, id: \.self) { day in
                            cell(for: day)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .cardStyle()
    }

    private func cell(for day: Date) -> some View {
        let stat = byKey[calendar.dayKey(for: day)]
        let value = stat.map { max(0, metric.value($0)) } ?? 0
        let intensity = value / maxValue
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(HeatmapColor.color(intensity: intensity))
            .frame(width: 13, height: 13)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(selectedDay?.dayKey == calendar.dayKey(for: day) ? Color.primary : Color.clear, lineWidth: 1.5)
            )
            .help(tooltip(day: day, stat: stat))
            .onTapGesture {
                if let stat {
                    selectedDay = stat
                } else {
                    selectedDay = DailyStatistics(aggregate: DailyAggregate(dayKey: calendar.dayKey(for: day), date: day))
                }
            }
    }

    private func tooltip(day: Date, stat: DailyStatistics?) -> String {
        guard let stat else { return Format.shortDayYear.string(from: day) + ": no activity" }
        return "\(Format.shortDayYear.string(from: day)): \(Format.int(stat.netWords)) words, \(Format.duration(stat.activeSeconds))"
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption).foregroundStyle(.secondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(HeatmapColor.color(intensity: value))
                    .frame(width: 13, height: 13)
            }
            Text("More").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dailyDetail(_ stat: DailyStatistics) -> some View {
        let sessions = (try? state.container.sessions.sessions(filter: SessionFilter(
            startDate: calendar.startOfDay(for: stat.date),
            endDate: calendar.endOfDay(for: stat.date)
        ))) ?? []
        let projects = (try? state.container.projects.allProjects()) ?? []
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: Format.day.string(from: stat.date), subtitle: "Daily detail")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Words", value: Format.int(stat.netWords))
                MetricTile(title: "Active", value: Format.duration(stat.activeSeconds))
                MetricTile(title: "Focus", value: Format.duration(stat.focusSeconds))
                MetricTile(title: "Sessions", value: "\(stat.sessionCount)")
                MetricTile(title: "WPM", value: stat.wordsPerMinute.map { Format.decimal($0) } ?? "—")
                MetricTile(title: "First session", value: stat.firstSessionAt.map { Format.time.string(from: $0) } ?? "—")
                MetricTile(title: "Last session", value: stat.lastSessionAt.map { Format.time.string(from: $0) } ?? "—")
                MetricTile(title: "Projects", value: "\(stat.projectCount)")
            }
            if sessions.isEmpty {
                Text("No sessions on this day.").foregroundStyle(.secondary)
            } else {
                Text("Sessions").font(.headline)
                ForEach(sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(names[session.projectID ?? ""] ?? "Unassigned").font(.subheadline.weight(.medium))
                            Text(Format.timeRange(session.startedAt, session.endedAt) + " · " + session.sessionType.displayName)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.netWordChange.map { ($0 >= 0 ? "+" : "") + Format.int($0) } ?? "—")
                            .font(.subheadline.monospacedDigit())
                    }
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func weekdayLabel(_ index: Int) -> String {
        let symbols = calendar.calendar.shortWeekdaySymbols
        let order: [Int]
        if calendar.calendar.firstWeekday == 1 {
            order = [1, 2, 3, 4, 5, 6, 7]
        } else {
            order = [2, 3, 4, 5, 6, 7, 1]
        }
        let weekday = order[index]
        return symbols[weekday - 1]
    }
}
