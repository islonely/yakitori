import SwiftUI
import Charts
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

/// Precomputed heatmap cell. Building these once avoids the O(n²) behaviour of
/// recomputing the lookup dictionary and maximum for every one of the ~370 cells.
private struct HeatmapCell: Identifiable {
    let id: String
    let date: Date
    let stat: DailyStatistics?
    let intensity: Double
}

struct CalendarView: View {
    @EnvironmentObject private var state: AppState
    @State private var metric: HeatmapMetric = .words
    @State private var selectedDay: DailyStatistics?

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    var body: some View {
        let weeks = buildHeatmap()
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Calendar", subtitle: "Your daily writing heatmap", symbol: "calendar")
                HStack {
                    Spacer()
                    Picker("Metric", selection: $metric) {
                        ForEach(HeatmapMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                heatmap(weeks)
                legend
                monthBarsCard
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

    /// Builds the whole heatmap model in a single O(n) pass.
    private func buildHeatmap() -> [[HeatmapCell]] {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.addingDays(-370, to: end)
        let days = statistics.dailyStatistics(from: start, to: end)
        let byKey = Dictionary(uniqueKeysWithValues: days.map { ($0.dayKey, $0) })
        let maxValue = max(1, days.map { max(0, metric.value($0)) }.max() ?? 1)

        guard let first = days.first?.date, let last = days.last?.date else { return [] }
        let gridStart = calendar.startOfWeek(for: first)
        var weeks: [[HeatmapCell]] = []
        var current: [HeatmapCell] = []
        for day in calendar.days(from: gridStart, through: last) {
            let key = calendar.dayKey(for: day)
            let stat = byKey[key]
            let value = stat.map { max(0, metric.value($0)) } ?? 0
            current.append(HeatmapCell(id: key, date: day, stat: stat, intensity: value / maxValue))
            if current.count == 7 {
                weeks.append(current)
                current = []
            }
        }
        if !current.isEmpty { weeks.append(current) }
        return weeks
    }

    private func heatmap(_ weeks: [[HeatmapCell]]) -> some View {
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
                        ForEach(week) { cell in
                            cellView(cell)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .cardStyle()
    }

    private func cellView(_ cell: HeatmapCell) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(HeatmapColor.color(intensity: cell.intensity))
            .frame(width: 13, height: 13)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(selectedDay?.dayKey == cell.id ? Color.primary : Color.clear, lineWidth: 1.5)
            )
            .help(tooltip(cell))
            .onTapGesture {
                selectedDay = cell.stat
                    ?? DailyStatistics(aggregate: DailyAggregate(dayKey: cell.id, date: cell.date))
            }
    }

    private func tooltip(_ cell: HeatmapCell) -> String {
        guard let stat = cell.stat else { return Format.shortDayYear.string(from: cell.date) + ": no activity" }
        return "\(Format.shortDayYear.string(from: cell.date)): \(Format.int(stat.netWords)) words, \(Format.duration(stat.activeSeconds))"
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

    private var monthBarsCard: some View {
        let monthStart = calendar.startOfMonth(for: selectedDay?.date ?? Date())
        let monthEnd = calendar.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? calendar.addingDays(31, to: monthStart)
        let days = statistics.dailyStatistics(from: monthStart, to: calendar.addingDays(-1, to: monthEnd))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Format.monthYear.string(from: monthStart), subtitle: "Daily output")
            Chart(days, id: \.dayKey) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.netWords))
                    .foregroundStyle(Theme.ember.gradient)
                    .cornerRadius(2)
            }
            .frame(height: 140)
        }
        .cardStyle()
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
