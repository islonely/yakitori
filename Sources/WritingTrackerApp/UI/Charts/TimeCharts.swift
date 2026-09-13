import SwiftUI
import Charts
import WritingTrackerCore

/// Daily bars with a 7-day and 30-day moving average line.
struct RollingAverageChart: View {
    let days: [DailyStatistics]
    var height: CGFloat = 240

    var body: some View {
        let values = days.map { Double($0.netWords) }
        let avg7 = StatisticsService.movingAverage(values, window: 7)
        let avg30 = StatisticsService.movingAverage(values, window: 30)
        Chart {
            ForEach(Array(days.enumerated()), id: \.element.dayKey) { (index, day) in
                BarMark(x: .value("Date", day.date, unit: .day), y: .value("Words", day.netWords))
                    .foregroundStyle(Theme.ember.opacity(0.35))
                if let value = avg7[index] {
                    LineMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("7-day average", value),
                        series: .value("Series", "7-day")
                    )
                    .foregroundStyle(Theme.ember)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let value = avg30[index] {
                    LineMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("30-day average", value),
                        series: .value("Series", "30-day")
                    )
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .frame(height: height)
        .chartForegroundStyleScale(["7-day": Theme.ember, "30-day": Theme.gold])
    }
}

/// This week vs last week, by weekday.
struct MomentumChart: View {
    let points: [WeekdayMomentum]
    var height: CGFloat = 180

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Weekday", Format.shortWeekday(point.weekday)), y: .value("Last week", point.lastWeek))
                    .foregroundStyle(Theme.gold.opacity(0.45))
                    .position(by: .value("Week", "Last week"))
                BarMark(x: .value("Weekday", Format.shortWeekday(point.weekday)), y: .value("This week", point.thisWeek))
                    .foregroundStyle(Theme.ember)
                    .position(by: .value("Week", "This week"))
            }
        }
        .frame(height: height)
        .chartForegroundStyleScale(["This week": Theme.ember, "Last week": Theme.gold.opacity(0.45)])
    }
}

/// A compact 24-hour bar strip.
struct HourlyBars: View {
    let values: [Double]
    var tint: Color = Theme.ember
    var height: CGFloat = 60

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { (index, value) in
            BarMark(x: .value("Hour", index), y: .value("Value", value))
                .foregroundStyle(tint.gradient)
                .cornerRadius(1.5)
        }
        .frame(height: height)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

enum MatrixMetric: String, CaseIterable, Identifiable {
    case words, activeMinutes, sessions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .words: return "Words"
        case .activeMinutes: return "Active time"
        case .sessions: return "Sessions"
        }
    }
    func value(_ cell: HourWeekdayCell) -> Double {
        switch self {
        case .words: return Double(cell.words)
        case .activeMinutes: return cell.activeSeconds / 60
        case .sessions: return 0
        }
    }
}

/// Day-of-week × hour heatmap.
struct HourWeekdayHeatmap: View {
    let cells: [HourWeekdayCell]
    let metric: MatrixMetric

    private var maxValue: Double {
        max(1, cells.map { max(0, metric.value($0)) }.max() ?? 1)
    }

    var body: some View {
        Chart(cells) { cell in
            RectangleMark(x: .value("Hour", cell.hour), y: .value("Weekday", Format.shortWeekday(cell.weekday)))
                .foregroundStyle(Theme.heatmapColor(metric.value(cell) / maxValue))
        }
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text(Format.hourLabel(hour)) }
                }
            }
        }
    }
}

/// Radial 24-hour "writing clock".
struct WritingClock: View {
    let values: [Double]
    var size: CGFloat = 240

    private var maxValue: Double { max(1, values.max() ?? 1) }

    var body: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { hour in
                let fraction = max(0, values[safe: hour] ?? 0) / maxValue
                Capsule()
                    .fill(Theme.heatmapColor(fraction))
                    .frame(width: size * 0.035, height: size * 0.10 + size * 0.34 * fraction)
                    .offset(y: -size * 0.20 - size * 0.17 * fraction)
                    .rotationEffect(.degrees(Double(hour) / 24.0 * 360.0))
            }
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: size * 0.34, height: size * 0.34)
            VStack(spacing: 0) {
                Image(systemName: "clock").foregroundStyle(Theme.accent)
                Text("24h").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Stacked focus vs active time per day.
struct FocusActiveStackChart: View {
    let days: [DailyStatistics]
    var height: CGFloat = 220

    private struct Slice: Identifiable {
        var id: String { "\(dayKey)-\(kind)" }
        let dayKey: String
        let date: Date
        let kind: String
        let seconds: Double
    }

    var body: some View {
        var slices: [Slice] = []
        for day in days {
            slices.append(Slice(dayKey: day.dayKey, date: day.date, kind: "Active", seconds: day.activeSeconds))
            let passive = max(0, day.focusSeconds - day.activeSeconds)
            slices.append(Slice(dayKey: day.dayKey, date: day.date, kind: "Reading / thinking", seconds: passive))
        }
        return Chart(slices) { slice in
            BarMark(x: .value("Date", slice.date, unit: .day), y: .value("Minutes", slice.seconds / 60))
                .foregroundStyle(by: .value("Kind", slice.kind))
        }
        .frame(height: height)
        .chartForegroundStyleScale(["Active": Theme.ember, "Reading / thinking": Theme.gold.opacity(0.6)])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
