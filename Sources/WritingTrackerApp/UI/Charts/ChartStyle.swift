import SwiftUI
import WritingTrackerCore

/// Palette helpers for multi-series charts.
enum ChartStyle {
    static let palette: [Color] = [
        Theme.ember,
        Theme.gold,
        Color(red: 0.20, green: 0.60, blue: 0.72), // teal
        Color(red: 0.55, green: 0.40, blue: 0.78), // violet
        Color(red: 0.28, green: 0.62, blue: 0.40), // green
        Color(red: 0.85, green: 0.45, blue: 0.60), // rose
        Color(red: 0.35, green: 0.48, blue: 0.78), // blue
        Color(red: 0.55, green: 0.52, blue: 0.48)  // warm gray
    ]

    static func color(at index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static func color(for type: SessionType) -> Color {
        switch type {
        case .drafting: return Theme.ember
        case .editing: return Theme.gold
        case .revising: return Color(red: 0.55, green: 0.40, blue: 0.78)
        case .proofreading: return Color(red: 0.20, green: 0.60, blue: 0.72)
        case .research: return Color(red: 0.28, green: 0.62, blue: 0.40)
        case .planning: return Color(red: 0.35, green: 0.48, blue: 0.78)
        case .other: return Color(red: 0.85, green: 0.45, blue: 0.60)
        case .unknown: return Color(red: 0.55, green: 0.52, blue: 0.48)
        }
    }

    static var sessionTypeDomain: [String] {
        SessionType.allCases.map(\.displayName)
    }

    static var sessionTypeRange: [Color] {
        SessionType.allCases.map { color(for: $0) }
    }
}
