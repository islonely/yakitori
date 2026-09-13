import SwiftUI
import Charts
import WritingTrackerCore

/// Cumulative progress with dashed pace projections to the target.
struct ProjectionConeChart: View {
    let cumulative: [CumulativePoint]
    let target: Int?
    let projections: [CompletionProjection]
    var height: CGFloat = 240

    var body: some View {
        Chart {
            ForEach(cumulative) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Words", point.words))
                    .foregroundStyle(Theme.ember.opacity(0.12).gradient)
                LineMark(x: .value("Date", point.date), y: .value("Words", point.words))
                    .foregroundStyle(Theme.ember)
            }
            if let target, let last = cumulative.last {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target \(Format.int(target))").font(.caption2).foregroundStyle(.secondary)
                    }
                ForEach(projections, id: \.label) { projection in
                    if projection.isSufficient, let date = projection.projectedDate {
                        LineMark(
                            x: .value("Date", last.date),
                            y: .value("Words", last.words),
                            series: .value("Projection", projection.label)
                        )
                        .foregroundStyle(.secondary)
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Words", target),
                            series: .value("Projection", projection.label)
                        )
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Remaining words over time against the straight required-pace line.
struct BurnDownChart: View {
    let cumulative: [CumulativePoint]
    let target: Int
    let required: [CumulativePoint]
    var height: CGFloat = 220

    var body: some View {
        Chart {
            ForEach(cumulative) { point in
                LineMark(x: .value("Date", point.date), y: .value("Remaining", max(0, target - point.words)), series: .value("Series", "Actual"))
                    .foregroundStyle(Theme.ember)
            }
            ForEach(required) { point in
                LineMark(x: .value("Date", point.date), y: .value("Remaining", max(0, target - point.words)), series: .value("Series", "Required"))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .frame(height: height)
        .chartForegroundStyleScale(["Actual": Theme.ember, "Required": Theme.gold])
        .chartYAxisLabel("words remaining")
    }
}

/// Word-count history, one line per document.
struct DocumentWordCountChart: View {
    let series: [DocumentWordSeries]
    var height: CGFloat = 220

    var body: some View {
        Chart {
            ForEach(series) { document in
                ForEach(document.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Words", point.words),
                        series: .value("Document", document.displayName)
                    )
                    .foregroundStyle(by: .value("Document", document.displayName))
                }
            }
        }
        .frame(height: height)
        .chartForegroundStyleScale(domain: series.map(\.displayName), range: series.enumerated().map { ChartStyle.color(at: $0.offset) })
    }
}

/// Horizontal milestone timeline.
struct MilestoneTimeline: View {
    let project: Project
    let milestones: [Milestone]
    let projectedCompletion: Date?

    private struct Entry: Identifiable {
        var id: String { title }
        let title: String
        let date: Date
        let done: Bool
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        if let started = project.startedAt {
            result.append(Entry(title: "Started", date: started, done: true))
        }
        for milestone in milestones {
            if let completed = milestone.completedAt {
                result.append(Entry(title: milestone.title, date: completed, done: true))
            }
        }
        if let completed = project.completedAt {
            result.append(Entry(title: "Completed", date: completed, done: true))
        }
        if let projected = projectedCompletion, project.completedAt == nil {
            result.append(Entry(title: "Projected completion", date: projected, done: false))
        }
        return result.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                Text("No milestones yet.").foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.done ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(entry.done ? Theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.subheadline.weight(.medium))
                            Text(Format.shortDayYear.string(from: entry.date))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if entry.id != entries.last?.id {
                        Rectangle().fill(Theme.ember.opacity(0.2)).frame(width: 1, height: 12).padding(.leading, 7)
                    }
                }
            }
        }
    }
}

/// Side-by-side project comparison bars for one metric.
struct ProjectComparisonChart: View {
    let items: [(name: String, value: Double)]
    let isTime: Bool
    var height: CGFloat = 220

    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { (_, item) in
            BarMark(x: .value("Project", item.name), y: .value("Value", item.value))
                .foregroundStyle(Theme.ember.gradient)
                .annotation(position: .top) {
                    Text(isTime ? Format.duration(item.value) : Format.int(Int(item.value.rounded())))
                        .font(.caption2).foregroundStyle(.secondary)
                }
        }
        .frame(height: height)
    }
}

/// Daily words stacked by project.
struct ProjectMixChart: View {
    let points: [ProjectDayWords]
    let projectNames: [String: String]
    var height: CGFloat = 220

    private func name(_ id: String?) -> String {
        guard let id else { return "Unassigned" }
        return projectNames[id] ?? "Project"
    }

    var body: some View {
        let names = Array(Set(points.map { name($0.projectID) })).sorted()
        Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Words", point.words)
            )
            .foregroundStyle(by: .value("Project", name(point.projectID)))
        }
        .frame(height: height)
        .chartForegroundStyleScale(domain: names, range: names.enumerated().map { ChartStyle.color(at: $0.offset) })
    }
}

/// Words per year, stacked by project type.
struct CareerOutputChart: View {
    let points: [YearTypeWords]
    var height: CGFloat = 220

    var body: some View {
        let types = Array(Set(points.map(\.type))).sorted { $0.rawValue < $1.rawValue }
        Chart(points) { point in
            BarMark(x: .value("Year", point.year), y: .value("Words", point.words))
                .foregroundStyle(by: .value("Type", point.type.displayName))
        }
        .frame(height: height)
        .chartForegroundStyleScale(domain: types.map(\.displayName), range: types.enumerated().map { ChartStyle.color(at: $0.offset) })
    }
}
