import SwiftUI
import Charts
import WritingTrackerCore

// MARK: - Shared containers

/// Card container with a built-in insufficient-data state.
struct AnalyticsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let isEmpty: Bool
    var emptyMessage: String = "Not enough data yet."
    var accessibilitySummary: String?
    var accessory: AnyView?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title, subtitle: subtitle)
                Spacer()
                if let accessory { accessory }
            }
            if isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: isEmpty ? .ignore : .combine)
        .accessibilityLabel(Text(accessibilitySummary ?? title))
    }
}

/// Compact row of distribution statistics.
struct DistributionStatsRow: View {
    let summary: DistributionSummary
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 16) {
            stat("Mean", summary.mean)
            stat("Median", summary.median)
            stat("P25", summary.p25)
            stat("P75", summary.p75)
            stat("Min", summary.minimum)
            stat("Max", summary.maximum)
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(format(value)).font(.caption.weight(.medium)).monospacedDigit()
        }
    }
}

// MARK: - 1. Session duration

struct SessionDurationHistogramChart: View {
    let distribution: SessionDurationDistribution

    var body: some View {
        AnalyticsCard(
            title: "Session duration",
            subtitle: "How long your sessions actually last",
            isEmpty: distribution.isEmpty,
            emptyMessage: "No completed sessions with a valid duration yet.",
            accessibilitySummary: accessibility
        ) {
            Chart(distribution.bins) { bin in
                BarMark(x: .value("Duration", bin.label), y: .value("Sessions", bin.count))
                    .foregroundStyle(Theme.ember.gradient)
                    .cornerRadius(2)
            }
            .frame(height: 190)
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.caption2) }
            }
            .accessibilityHidden(true)

            HStack(spacing: 14) {
                marker("Median", Theme.ember)
                marker("Mean", Theme.gold)
            }
            DistributionStatsRow(summary: distribution.summary) { "\(Int($0.rounded()))m" }
        }
    }

    private func marker(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 3, height: 12)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var accessibility: String {
        let s = distribution.summary
        return "Session duration histogram. \(distribution.sessionCount) sessions. Median \(Int(s.median.rounded())) minutes, mean \(Int(s.mean.rounded())) minutes."
    }
}

// MARK: - 2. Daily output distribution

struct DailyOutputHistogramChart: View {
    let distribution: DailyOutputDistribution
    var accessory: AnyView?

    var body: some View {
        AnalyticsCard(
            title: "Daily output distribution",
            subtitle: distribution.metric.isEstimated
                ? "Gross words worked per writing day (estimated)"
                : "Net words per writing day",
            isEmpty: distribution.isEmpty,
            emptyMessage: "No writing days in this range.",
            accessibilitySummary: accessibility,
            accessory: accessory
        ) {
            Chart(distribution.bins) { bin in
                BarMark(x: .value("Words", bin.label), y: .value("Days", bin.count))
                    .foregroundStyle(Theme.ember.gradient)
                    .cornerRadius(2)
            }
            .frame(height: 190)
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.caption2) }
            }
            .accessibilityHidden(true)
            DistributionStatsRow(summary: distribution.summary) { Format.int(Int($0.rounded())) }
        }
    }

    private var accessibility: String {
        let s = distribution.summary
        return "Daily output histogram. \(distribution.writingDayCount) writing days. Median \(Int(s.median.rounded())) words."
    }
}

// MARK: - 3. Productivity by session length

struct ProductivityByLengthChart: View {
    let data: SessionLengthProductivity

    private var sufficientBins: [SessionLengthProductivityBin] {
        data.bins.filter { $0.isSufficient }
    }

    var body: some View {
        AnalyticsCard(
            title: "Productivity by session length",
            subtitle: "Median net words per active hour for each duration (minimum \(data.minimumSampleSize) sessions)",
            isEmpty: sufficientBins.isEmpty,
            emptyMessage: "Not enough sessions in any duration band yet.",
            accessibilitySummary: accessibility
        ) {
            Chart(sufficientBins) { bin in
                RuleMark(
                    x: .value("Bin", bin.label),
                    yStart: .value("P25", bin.p25WordsPerHour),
                    yEnd: .value("P75", bin.p75WordsPerHour)
                )
                .foregroundStyle(Theme.ember.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 6))
                PointMark(x: .value("Bin", bin.label), y: .value("Median", bin.medianWordsPerHour))
                    .foregroundStyle(Theme.ember)
                    .symbolSize(60)
                    .annotation(position: .top) {
                        Text("n=\(bin.sampleCount)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 200)
            .chartYAxisLabel("words / hour")
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.caption2) }
            }
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        let text = sufficientBins.map { "\($0.label): \(Int($0.medianWordsPerHour.rounded())) words per hour, \($0.sampleCount) sessions" }.joined(separator: ". ")
        return "Productivity by session length. \(text)"
    }
}

// MARK: - 4. Goal performance history

struct GoalPerformanceChart: View {
    let history: GoalPerformanceHistory
    var accessory: AnyView?

    var body: some View {
        AnalyticsCard(
            title: "Goal performance",
            subtitle: "\(history.period.displayName) attainment across completed periods",
            isEmpty: history.isEmpty,
            emptyMessage: "No completed \(history.period.displayName.lowercased()) goal periods yet.",
            accessibilitySummary: accessibility,
            accessory: accessory
        ) {
            Chart {
                ForEach(history.results) { result in
                    LineMark(x: .value("Period", result.start), y: .value("Attainment", result.attainment))
                        .foregroundStyle(Theme.ember.opacity(0.4))
                }
                ForEach(history.results) { result in
                    PointMark(x: .value("Period", result.start), y: .value("Attainment", result.attainment))
                        .foregroundStyle(by: .value("Result", category(result.attainment)))
                        .symbolSize(48)
                }
                RuleMark(y: .value("Target", 100))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("100%").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 200)
            .chartYAxisLabel("% of target")
            .chartForegroundStyleScale(["Met": Color.green, "Close": Theme.gold, "Missed": Theme.ember])
            .accessibilityHidden(true)

            HStack(spacing: 16) {
                summaryStat("Met", "\(history.met)")
                summaryStat("Missed", "\(history.missed)")
                summaryStat("Success", Format.percent(history.successRate))
                summaryStat("Median", Format.percent(min(1, history.medianAttainment / 100)))
                summaryStat("Best run", "\(history.longestSuccessRun)")
            }
            HStack(spacing: 14) {
                legend("Met", .green)
                legend("Close", Theme.gold)
                legend("Missed", Theme.ember)
            }
        }
    }

    private func category(_ attainment: Double) -> String {
        if attainment >= 100 { return "Met" }
        if attainment >= 80 { return "Close" }
        return "Missed"
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium))
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var accessibility: String {
        "Goal performance. \(history.met) met, \(history.missed) missed, success rate \(Int((history.successRate * 100).rounded())) percent."
    }
}

// MARK: - 5. Project velocity

struct ProjectVelocityChart: View {
    let velocity: ProjectVelocity
    var accessory: AnyView?

    var body: some View {
        AnalyticsCard(
            title: "Project velocity",
            subtitle: velocity.hasRollingSeries
                ? "Words per \(velocity.granularity == .daily ? "day" : "week") with a rolling average"
                : "Words per \(velocity.granularity == .daily ? "day" : "week")",
            isEmpty: !velocity.hasSufficientData,
            emptyMessage: "Not enough project activity in this range.",
            accessibilitySummary: accessibility,
            accessory: accessory
        ) {
            Chart {
                ForEach(velocity.points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: velocity.granularity == .daily ? .day : .weekOfYear),
                        y: .value("Words", point.words)
                    )
                    .foregroundStyle(Theme.ember.opacity(0.35))
                }
                if velocity.hasRollingSeries {
                    ForEach(velocity.points) { point in
                        if let rolling = point.rollingAverage {
                            LineMark(
                                x: .value("Date", point.date, unit: velocity.granularity == .daily ? .day : .weekOfYear),
                                y: .value("Rolling", rolling)
                            )
                            .foregroundStyle(Theme.ember)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
            }
            .frame(height: 200)
            .chartYAxisLabel("words")
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        guard let last = velocity.points.last else { return "Project velocity. No data." }
        return "Project velocity. Latest period \(last.words) words."
    }
}

// MARK: - 6. Writing cadence

struct WritingCadenceHistogramChart: View {
    let cadence: WritingCadence

    var body: some View {
        AnalyticsCard(
            title: "Writing cadence",
            subtitle: "Time between the end of one session and the start of the next",
            isEmpty: cadence.isEmpty,
            emptyMessage: "Need at least two sessions to measure gaps.",
            accessibilitySummary: accessibility
        ) {
            Chart(cadence.bins) { bin in
                BarMark(x: .value("Gap", bin.label), y: .value("Gaps", bin.count))
                    .foregroundStyle(Theme.ember.gradient)
                    .cornerRadius(2)
            }
            .frame(height: 190)
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.caption2) }
            }
            .accessibilityHidden(true)
            DistributionStatsRow(summary: cadence.summary, format: Format.durationMinutes)
        }
    }

    private var accessibility: String {
        "Writing cadence histogram. \(cadence.gapCount) gaps. Median \(Int(cadence.summary.median.rounded())) minutes."
    }
}

// MARK: - 7. Project effort by phase

struct PhaseEffortChart: View {
    let efforts: [ProjectPhaseEffort]

    private var nonEmpty: [ProjectPhaseEffort] { efforts.filter { !$0.isEmpty } }

    var body: some View {
        AnalyticsCard(
            title: "Effort by phase",
            subtitle: "Share of active time per session type",
            isEmpty: nonEmpty.isEmpty,
            emptyMessage: "No active time recorded for these projects.",
            accessibilitySummary: accessibility
        ) {
            Chart {
                ForEach(nonEmpty) { effort in
                    ForEach(effort.slices) { slice in
                        BarMark(
                            x: .value("Percent", slice.fraction * 100),
                            y: .value("Project", effort.projectName)
                        )
                        .foregroundStyle(by: .value("Phase", slice.type.displayName))
                    }
                }
            }
            .frame(height: max(80, CGFloat(nonEmpty.count) * 46))
            .chartXAxisLabel("% of active time")
            .chartForegroundStyleScale(domain: ChartStyle.sessionTypeDomain, range: ChartStyle.sessionTypeRange)
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        nonEmpty.map { effort in
            let phases = effort.slices.map { "\($0.type.displayName) \(Int(($0.fraction * 100).rounded())) percent" }.joined(separator: ", ")
            return "\(effort.projectName): \(phases)"
        }.joined(separator: ". ")
    }
}

// MARK: - 8. Cumulative lifetime output

struct CumulativeOutputChart: View {
    let points: [CumulativeOutputPoint]
    let metric: CumulativeOutputMetric
    var accessory: AnyView?

    var body: some View {
        AnalyticsCard(
            title: "Cumulative lifetime output",
            subtitle: metric.isEstimated
                ? "Gross words worked (estimated), cumulated"
                : "Net manuscript words, cumulated",
            isEmpty: points.count < 2,
            emptyMessage: "No writing history yet.",
            accessibilitySummary: accessibility,
            accessory: accessory
        ) {
            Chart(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Words", point.value))
                    .foregroundStyle(Theme.ember.opacity(0.15).gradient)
                LineMark(x: .value("Date", point.date), y: .value("Words", point.value))
                    .foregroundStyle(Theme.ember)
            }
            .frame(height: 220)
            .chartYAxisLabel("cumulative words")
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        guard let last = points.last else { return "Cumulative output. No data." }
        return "Cumulative output. Total \(last.value) words by \(Format.shortDayYear.string(from: last.date))."
    }
}

// MARK: - 9. Productivity variability

struct VariabilityChart: View {
    let series: OutputVariability

    /// Uses coefficient of variation when available, otherwise standard deviation.
    private var usesCV: Bool { series.points.contains { $0.coefficientOfVariation != nil } }

    private struct Point: Identifiable {
        var id: String { "\(date.timeIntervalSince1970)" }
        let date: Date
        let value: Double
        let point: VariabilityPoint
    }

    private var plotted: [Point] {
        series.points.compactMap { point in
            if usesCV, let cv = point.coefficientOfVariation {
                return Point(date: point.date, value: cv, point: point)
            }
            if !usesCV {
                return Point(date: point.date, value: point.standardDeviation, point: point)
            }
            return nil
        }
    }

    var body: some View {
        AnalyticsCard(
            title: "Output variability",
            subtitle: usesCV
                ? "Rolling \(series.window)-writing-day coefficient of variation (lower is steadier)"
                : "Rolling \(series.window)-writing-day standard deviation",
            isEmpty: plotted.isEmpty,
            emptyMessage: "Need at least \(series.window) writing days for this window.",
            accessibilitySummary: accessibility
        ) {
            Chart(plotted) { item in
                LineMark(x: .value("Date", item.date), y: .value("Variability", item.value))
                    .foregroundStyle(Theme.ember)
                AreaMark(x: .value("Date", item.date), y: .value("Variability", item.value))
                    .foregroundStyle(Theme.ember.opacity(0.12).gradient)
            }
            .frame(height: 200)
            .chartYAxisLabel(usesCV ? "coefficient of variation" : "std. deviation (words)")
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        guard let last = plotted.last else { return "Output variability. Not enough data." }
        return "Output variability. Latest \(usesCV ? "coefficient of variation" : "standard deviation") \(Format.decimal(last.value, places: 2))."
    }
}

// MARK: - 10. Productivity by work type

struct WorkTypeProductivityChart: View {
    let items: [WorkTypeProductivity]

    private var sufficient: [WorkTypeProductivity] {
        items.filter { $0.isSufficient && $0.medianWordsPerHour != nil }
    }

    var body: some View {
        AnalyticsCard(
            title: "Productivity by work type",
            subtitle: "Median net words per active hour (descriptive, not a ranking of value)",
            isEmpty: sufficient.isEmpty,
            emptyMessage: "Not enough sessions of any type yet.",
            accessibilitySummary: accessibility
        ) {
            Chart(sufficient) { item in
                if let p25 = item.p25WordsPerHour, let p75 = item.p75WordsPerHour {
                    RuleMark(
                        xStart: .value("P25", p25),
                        xEnd: .value("P75", p75),
                        y: .value("Type", item.type.displayName)
                    )
                    .foregroundStyle(Theme.ember.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 6))
                }
                PointMark(
                    x: .value("Median", item.medianWordsPerHour ?? 0),
                    y: .value("Type", item.type.displayName)
                )
                .foregroundStyle(Theme.ember)
                .symbolSize(60)
                .annotation(position: .trailing) {
                    Text("n=\(item.sampleCount)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: max(100, CGFloat(sufficient.count) * 40))
            .chartXAxisLabel("words / hour")
            .accessibilityHidden(true)
        }
    }

    private var accessibility: String {
        sufficient.map { "\($0.type.displayName): median \(Int(($0.medianWordsPerHour ?? 0).rounded())) words per hour, \($0.sampleCount) sessions" }
            .joined(separator: ". ")
    }
}
