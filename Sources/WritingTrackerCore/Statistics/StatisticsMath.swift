import Foundation

/// Pure statistical helpers shared by the analytics calculators.
///
/// These are deliberately free of any business assumptions (active time, net
/// words, etc.); the analytics services decide which values to feed in.
public enum StatisticsMath {
    public static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n - 1). Returns 0 for fewer than two values.
    public static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// Linear-interpolation percentile. `percentile` is in the 0...1 range.
    public static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(1, max(0, percentile)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    public static func median(_ values: [Double]) -> Double {
        percentile(values, 0.5)
    }

    public static func summary(_ values: [Double]) -> DistributionSummary {
        guard !values.isEmpty else { return .empty }
        return DistributionSummary(
            count: values.count,
            mean: mean(values),
            median: median(values),
            p25: percentile(values, 0.25),
            p75: percentile(values, 0.75),
            minimum: values.min() ?? 0,
            maximum: values.max() ?? 0
        )
    }

    /// Counts values into fixed bins. The final bin includes its upper edge.
    public static func binCounts(_ values: [Double], edges: [Double]) -> [Int] {
        guard edges.count >= 2 else { return [] }
        var counts = [Int](repeating: 0, count: edges.count - 1)
        for value in values {
            for index in 0..<counts.count {
                let lower = edges[index]
                let upper = edges[index + 1]
                let isLast = index == counts.count - 1
                if value >= lower && (value < upper || (isLast && value <= upper)) {
                    counts[index] += 1
                    break
                }
            }
        }
        return counts
    }

    /// Builds evenly spaced edges covering `values`, or nil when there is nothing
    /// to bin or every value is identical.
    public static func equalWidthEdges(_ values: [Double], binCount: Int) -> [Double]? {
        guard let minimum = values.min(), let maximum = values.max(), binCount > 0, maximum > minimum else {
            return nil
        }
        let width = (maximum - minimum) / Double(binCount)
        return (0...binCount).map { minimum + Double($0) * width }
    }
}

/// Summary of a distribution of values.
public struct DistributionSummary: Hashable, Sendable {
    public let count: Int
    public let mean: Double
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let minimum: Double
    public let maximum: Double

    public init(
        count: Int,
        mean: Double,
        median: Double,
        p25: Double,
        p75: Double,
        minimum: Double,
        maximum: Double
    ) {
        self.count = count
        self.mean = mean
        self.median = median
        self.p25 = p25
        self.p75 = p75
        self.minimum = minimum
        self.maximum = maximum
    }

    public var isEmpty: Bool { count == 0 }

    public static let empty = DistributionSummary(
        count: 0, mean: 0, median: 0, p25: 0, p75: 0, minimum: 0, maximum: 0
    )
}

/// One bin of a histogram.
public struct HistogramBin: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let lowerBound: Double
    public let upperBound: Double
    public let count: Int

    public init(label: String, lowerBound: Double, upperBound: Double, count: Int) {
        self.label = label
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.count = count
    }
}
