import SwiftUI
import WritingTrackerCore

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
