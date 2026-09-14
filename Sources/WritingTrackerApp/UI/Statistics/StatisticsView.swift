import SwiftUI
import Charts
import WritingTrackerCore

struct StatisticsView: View {
    @EnvironmentObject private var state: AppState
    @State private var range: DateRangeOption = .thisMonth
    @State private var matrixMetric: MatrixMetric = .words
    @State private var dailyMetric: DailyOutputMetric = .netWords
    @State private var goalPeriod: GoalPeriod = .daily
    @State private var cumulativeMetric: CumulativeOutputMetric = .netWords

    private var statistics: StatisticsService { state.container.statistics }
    private var analytics: AnalyticsService { state.container.analytics }
    private var calendar: CalendarContext { statistics.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader(title: "Statistics", subtitle: "Your writing output and patterns", symbol: "chart.bar.xaxis")
                summaryGrid
                recordsSection
                lifetimeSection
                cumulativeOutputCard
                goalPerformanceCard
                rollingAverageChart
                dailyOutputDistributionCard
                HStack(alignment: .top, spacing: 16) {
                    activeTimeChart
                    writingClockCard
                }
                matrixCard
                scatterCard
                HStack(alignment: .top, spacing: 16) {
                    sessionDurationCard
                    productivityByLengthCard
                }
                HStack(alignment: .top, spacing: 16) {
                    paceTrendCard
                    paceHistogramCard
                }
                HStack(alignment: .top, spacing: 16) {
                    variabilityCard
                    cadenceCard
                }
                HStack(alignment: .top, spacing: 16) {
                    focusActiveCard
                    sessionTypeCard
                }
                workTypeCard
                projectMixCard
                HStack(alignment: .top, spacing: 16) {
                    streakLadderCard
                    addedRemovedCard
                }
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $range) {
                    ForEach(DateRangeOption.allCases.filter { $0 != .allTime }) { option in
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

    private var sessionFilter: SessionFilter {
        SessionFilter(startDate: interval.start, endDate: interval.end)
    }

    private var cumulativeOutputCard: some View {
        CumulativeOutputChart(
            points: analytics.cumulativeLifetimeOutput(metric: cumulativeMetric),
            metric: cumulativeMetric,
            accessory: AnyView(cumulativeMetricPicker)
        )
    }

    private var cumulativeMetricPicker: some View {
        Picker("Metric", selection: $cumulativeMetric) {
            ForEach(CumulativeOutputMetric.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
    }

    private var goalPerformanceCard: some View {
        GoalPerformanceChart(history: analytics.goalPerformance(period: goalPeriod), accessory: AnyView(goalPeriodPicker))
    }

    private var goalPeriodPicker: some View {
        Picker("Period", selection: $goalPeriod) {
            ForEach([GoalPeriod.daily, .weekly, .monthly]) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
    }

    private var dailyOutputDistributionCard: some View {
        DailyOutputHistogramChart(
            distribution: analytics.dailyOutputDistribution(range: interval, metric: dailyMetric),
            accessory: AnyView(dailyMetricPicker)
        )
    }

    private var dailyMetricPicker: some View {
        Picker("Metric", selection: $dailyMetric) {
            ForEach(DailyOutputMetric.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
    }

    private var sessionDurationCard: some View {
        SessionDurationHistogramChart(distribution: analytics.sessionDurationDistribution(filter: sessionFilter))
    }

    private var productivityByLengthCard: some View {
        ProductivityByLengthChart(data: analytics.productivityBySessionLength(filter: sessionFilter))
    }

    private var variabilityCard: some View {
        VariabilityChart(series: analytics.outputVariability(window: 7, range: interval))
    }

    private var cadenceCard: some View {
        WritingCadenceHistogramChart(cadence: analytics.writingCadence(filter: sessionFilter))
    }

    private var workTypeCard: some View {
        WorkTypeProductivityChart(items: analytics.productivityByWorkType(filter: sessionFilter))
    }

    private var rollingAverageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily output with trend", subtitle: "Bars plus 7-day and 30-day averages")
            RollingAverageChart(days: days)
        }
        .cardStyle()
    }

    private var writingClockCard: some View {
        let cells = statistics.hourWeekdayMatrix(from: interval.start, to: interval.end)
        var hourly = [Double](repeating: 0, count: 24)
        for cell in cells { hourly[cell.hour] += Double(cell.words) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Writing clock", subtitle: "Words by hour, \(range.title.lowercased())")
            HStack { Spacer(); WritingClock(values: hourly, size: 200); Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var matrixCard: some View {
        let cells = statistics.hourWeekdayMatrix(from: interval.start, to: interval.end)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "When you write", subtitle: "Day of week by hour")
                Spacer()
                Picker("Metric", selection: $matrixMetric) {
                    ForEach(MatrixMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            HourWeekdayHeatmap(cells: cells, metric: matrixMetric)
        }
        .cardStyle()
    }

    private var scatterCard: some View {
        let points = statistics.sessionPoints(filter: SessionFilter(startDate: interval.start, endDate: interval.end))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Session efficiency", subtitle: "Active minutes vs net words, by session type")
            if points.isEmpty {
                Text("No sessions in this range.").foregroundStyle(.secondary).frame(height: 160)
            } else {
                SessionScatterChart(points: points)
            }
        }
        .cardStyle()
    }

    private var paceTrendCard: some View {
        let points = statistics.paceHistory(from: interval.start, to: interval.end)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Pace over time", subtitle: "Estimated from document character growth")
            if points.isEmpty {
                Text("No character data yet. Pace appears for Word and Pages sessions.")
                    .font(.caption).foregroundStyle(.secondary).frame(height: 160)
            } else {
                PaceTrendChart(points: points)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var paceHistogramCard: some View {
        let points = statistics.paceHistory(from: interval.start, to: interval.end)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Pace distribution")
            if points.isEmpty {
                Text("No data yet.").foregroundStyle(.secondary).frame(height: 160)
            } else {
                PaceHistogramChart(points: points)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var focusActiveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Focus vs active", subtitle: "Active input time vs reading/thinking time")
            FocusActiveStackChart(days: days)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var sessionTypeCard: some View {
        let points = statistics.sessionTypeBreakdown(from: interval.start, to: interval.end)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Session types", subtitle: "Net words by type")
            if points.isEmpty {
                Text("No sessions in this range.").foregroundStyle(.secondary).frame(height: 160)
            } else {
                SessionTypeStackChart(days: points)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var projectMixCard: some View {
        let points = statistics.dailyWordsByProject(from: interval.start, to: interval.end)
        let projects = (try? state.container.projects.allProjects()) ?? []
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Project mix", subtitle: "Daily words by project")
            if points.isEmpty {
                Text("No project activity in this range.").foregroundStyle(.secondary).frame(height: 160)
            } else {
                ProjectMixChart(points: points, projectNames: names)
            }
        }
        .cardStyle()
    }

    private var streakLadderCard: some View {
        let runs = statistics.streakHistory()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Streak history")
            if runs.isEmpty {
                Text("No streaks yet.").foregroundStyle(.secondary).frame(height: 140)
            } else {
                StreakLadderChart(runs: runs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var addedRemovedCard: some View {
        let points = statistics.addedRemovedSeries(from: interval.start, to: interval.end)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Added vs removed", subtitle: "Estimated where exact edits are unavailable")
            if points.isEmpty {
                Text("No data in this range.").foregroundStyle(.secondary).frame(height: 140)
            } else {
                AddedRemovedChart(points: points)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var recordsSection: some View {
        let lifetime = statistics.lifetimeStatistics()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Personal records")
            RecordsStrip(lifetime: lifetime, bestWeek: bestWeekWords())
        }
        .cardStyle()
    }

    private func bestWeekWords() -> Int {
        let recent = statistics.dailyStatistics(from: calendar.addingDays(-730, to: Date()), to: Date())
        var totals: [String: Int] = [:]
        for stat in recent {
            totals[calendar.weekKey(for: stat.date), default: 0] += stat.netWords
        }
        return totals.values.max() ?? 0
    }

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
                MetricTile(title: "First tracked", value: lifetime.firstTrackedDay.map { Format.shortDayYear.string(from: $0) } ?? "—", systemImage: "flag")
                MetricTile(title: "Avg / session", value: Format.int(Int(lifetime.averageWordsPerSession.rounded())), systemImage: "chart.bar")
            }
        }
        .cardStyle()
    }
}
