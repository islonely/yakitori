import SwiftUI
import Charts
import WritingTrackerCore

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @State private var range: DateRangeOption = .today

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                primaryCards
                if range.isSingleDay {
                    timelineCard
                } else {
                    rollingAverageCard
                }
                momentumCard
                currentProjectCard
                goalsGrid
                recentSessionsCard
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(DateRangeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }

    private var header: some View {
        BrandHeader(title: greeting, subtitle: Format.day.string(from: Date()), symbol: "chart.line.uptrend.xyaxis")
    }

    private var greeting: String {
        let hour = calendar.hour(of: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night writing"
        }
    }

    private var rangeStats: PeriodStatistics {
        let interval = range.interval(calendar: calendar)
        return statistics.periodStatistics(start: interval.start, end: interval.end)
    }

    private var primaryCards: some View {
        let stats = rangeStats
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            StatCard(title: range == .today ? "Today's words" : "Net words", value: Format.int(stats.netWords),
                     subtitle: "Net manuscript change", systemImage: "text.word.spacing")
            StatCard(title: "Active time", value: Format.duration(stats.activeSeconds),
                     subtitle: "\(stats.sessions) sessions", systemImage: "clock")
            StatCard(title: "Writing days", value: "\(stats.writingDays)",
                     subtitle: "of \(max(stats.scheduledDays, 1)) scheduled", systemImage: "calendar.day.timeline.left")
            StatCard(title: "Current streak", value: "\(streak) days",
                     subtitle: "Longest \(longestStreak)", systemImage: "flame")
        }
    }

    private var timelineCard: some View {
        let day = range == .yesterday ? calendar.addingDays(-1, to: Date()) : Date()
        let hours = statistics.hourlyStatistics(for: day)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today's timeline", subtitle: "Net words by hour")
            Chart(hours, id: \.hour) { hour in
                BarMark(
                    x: .value("Hour", hour.hour),
                    y: .value("Words", hour.netWords)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hourLabel(hour))
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 180)
        }
        .cardStyle()
    }

    private var rollingAverageCard: some View {
        let interval = range.interval(calendar: calendar)
        let start = range == .allTime ? calendar.addingDays(-89, to: calendar.startOfDay(for: Date())) : interval.start
        let days = statistics.dailyStatistics(from: start, to: calendar.addingDays(-1, to: interval.end))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily output with trend", subtitle: "Bars plus 7-day and 30-day averages")
            RollingAverageChart(days: days)
        }
        .cardStyle()
    }

    private var momentumCard: some View {
        let points = statistics.weekdayMomentum(reference: Date())
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This week vs last week", subtitle: "Net words by weekday")
            MomentumChart(points: points)
        }
        .cardStyle()
    }

    private var goalsGrid: some View {
        let progress = statistics.goalProgress()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Goal progress")
            if progress.isEmpty {
                Text("No goals configured yet. Add one in Goals.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                    ForEach(progress) { item in
                        VStack(spacing: 6) {
                            ProgressRing(fraction: item.fraction, lineWidth: 8)
                                .scaleEffect(0.72)
                                .frame(height: 78)
                            Text(item.goal.period.displayName + " · " + item.goal.metric.displayName)
                                .font(.caption)
                            Text("\(Format.int(Int(item.currentValue))) / \(Format.int(Int(item.goal.target)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var currentProjectCard: some View {
        let project = state.currentProject
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Current project")
            if let project {
                HStack(spacing: 16) {
                    ProgressRing(fraction: project.progressFraction ?? 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title).font(.headline)
                        Text("\(Format.int(project.currentWordCount)) words")
                            .font(.callout).foregroundStyle(.secondary)
                        if let target = project.targetWordCount {
                            Text("Target \(Format.int(target))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let deadline = project.deadline {
                            Text("Deadline \(Format.shortDayYear.string(from: deadline))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            } else {
                Text("No current project selected.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var recentSessionsCard: some View {
        let sessions = (try? state.container.sessions.sessions(filter: SessionFilter())) ?? []
        let recent = Array(sessions.prefix(6))
        let projects = (try? state.container.projects.allProjects()) ?? []
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Recent sessions")
                Spacer()
                Button("View all") { state.selectedSection = .sessions }
                    .buttonStyle(.link)
            }
            if recent.isEmpty {
                Text("No sessions recorded yet. Start writing to see them here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(projectNames[session.projectID ?? ""] ?? "Unassigned")
                                .font(.subheadline.weight(.medium))
                            Text("\(Format.shortDay.string(from: session.startedAt)) · \(Format.time.string(from: session.startedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(session.netWordChange.map { ($0 >= 0 ? "+" : "") + Format.int($0) } ?? "—")
                                .font(.subheadline.monospacedDigit())
                            Text(Format.duration(session.activeSeconds))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if session.id != recent.last?.id { Divider() }
                }
            }
        }
        .cardStyle()
    }

    private var streak: Int { statistics.streakStatistics().currentStreak }
    private var longestStreak: Int { statistics.streakStatistics().longestStreak }

    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display)\(suffix)"
    }
}
