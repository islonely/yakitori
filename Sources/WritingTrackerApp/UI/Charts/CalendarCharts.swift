import SwiftUI
import WritingTrackerCore

/// A whole year as a compact month × day grid of pixels.
struct YearInPixelsView: View {
    let days: [DailyStatistics]
    let metric: HeatmapMetric

    private var maxValue: Double {
        max(1, days.map { max(0, metric.value($0)) }.max() ?? 1)
    }

    private var grid: [[DailyStatistics?]] {
        var result: [[DailyStatistics?]] = Array(repeating: Array(repeating: nil, count: 31), count: 12)
        for stat in days {
            let comps = Calendar.current.dateComponents([.month, .day], from: stat.date)
            guard let month = comps.month, let day = comps.day, month >= 1, month <= 12, day >= 1, day <= 31 else { continue }
            result[month - 1][day - 1] = stat
        }
        return result
    }

    var body: some View {
        let matrix = grid
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<12, id: \.self) { month in
                HStack(spacing: 3) {
                    Text(Format.shortMonth(month))
                        .font(.system(size: 9))
                        .frame(width: 26, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    ForEach(0..<31, id: \.self) { day in
                        let stat = matrix[month][day]
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Theme.heatmapColor((stat.map { metric.value($0) } ?? 0) / maxValue))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }
}

/// Months × years heatmap.
struct MonthlyYearGrid: View {
    let cells: [MonthlyYearCell]

    private var years: [Int] { Array(Set(cells.map(\.year))).sorted() }
    private var maxValue: Int { max(1, cells.map(\.words).max() ?? 1) }
    private var lookup: [String: Int] {
        Dictionary(uniqueKeysWithValues: cells.map { ("\($0.year)-\($0.month)", $0.words) })
    }

    var body: some View {
        let map = lookup
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text("").frame(width: 42)
                ForEach(1...12, id: \.self) { month in
                    Text(Format.shortMonth(month))
                        .font(.system(size: 9))
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(years, id: \.self) { year in
                HStack(spacing: 3) {
                    Text(String(year))
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 42, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    ForEach(1...12, id: \.self) { month in
                        let words = map["\(year)-\(month)"] ?? 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.heatmapColor(Double(max(0, words)) / Double(maxValue)))
                            .frame(width: 22, height: 18)
                            .overlay(
                                Text(words > 0 ? Format.compact(words) : "")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.white.opacity(0.85))
                            )
                    }
                }
            }
        }
    }
}
