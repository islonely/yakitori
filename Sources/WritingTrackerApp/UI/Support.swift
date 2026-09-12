import SwiftUI
import WritingTrackerCore

// MARK: - Formatting

enum Format {
    static func int(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func compact(_ value: Int) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func duration(_ seconds: Double) -> String {
        DurationFormatter.short(seconds)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func decimal(_ value: Double, places: Int = 1) -> String {
        String(format: "%.\(places)f", value)
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let shortDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static func timeRange(_ start: Date, _ end: Date?) -> String {
        guard let end else { return time.string(from: start) }
        return "\(time.string(from: start)) – \(time.string(from: end))"
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.ember.opacity(0.035))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.ember.opacity(0.14))
            )
            .shadow(color: Theme.ember.opacity(0.07), radius: 10, y: 4)
    }
}

// MARK: - Components

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [Theme.ember, Theme.gold, Theme.ember], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
            Text(Format.percent(fraction))
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .frame(width: 96, height: 96)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct PermissionBadge: View {
    let state: PermissionState

    var body: some View {
        Text(state.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch state {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        case .notApplicable: return .secondary
        }
    }
}

enum HeatmapColor {
    static func color(intensity: Double) -> Color {
        Theme.heatmapColor(intensity)
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Small view that observes the high-frequency tracking model on its own, so
/// heavy screens (e.g. Settings) do not re-render on every activity tick.
struct TrackingStatusLabel: View {
    @EnvironmentObject private var tracking: TrackingModel

    var body: some View {
        Text(tracking.snapshot.isSessionOpen ? "Tracking" : "Idle")
            .foregroundStyle(.secondary)
    }
}
