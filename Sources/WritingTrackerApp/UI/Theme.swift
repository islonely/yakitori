import SwiftUI

/// Yakitori's visual identity: a warm charcoal-and-ember palette inspired by a
/// grill. Centralised so the whole app stays consistent.
enum Theme {
    static let ember = Color(red: 0.93, green: 0.33, blue: 0.15)
    static let emberDeep = Color(red: 0.64, green: 0.13, blue: 0.07)
    static let gold = Color(red: 0.98, green: 0.70, blue: 0.25)
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.91)
    static let charcoal = Color(red: 0.10, green: 0.09, blue: 0.09)

    /// Primary interactive/brand colour. Used as the app tint.
    static let accent = ember

    static let brandGradient = LinearGradient(
        colors: [ember, gold],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chartGradient = LinearGradient(
        colors: [ember, gold.opacity(0.85)],
        startPoint: .bottom,
        endPoint: .top
    )

    static let headerGradient = LinearGradient(
        colors: [ember.opacity(0.20), gold.opacity(0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sidebarGradient = LinearGradient(
        colors: [ember.opacity(0.22), gold.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )

    static func heatmapColor(_ intensity: Double) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.06) }
        let t = min(1, max(0, intensity))
        // Interpolate ember -> gold.
        return Color(red: 0.93 + 0.05 * t, green: 0.33 + 0.37 * t, blue: 0.15 + 0.10 * t)
    }
}

/// The Yakitori logo mark: a woodblock-style rounded tile with an ember flame.
struct YakitoriMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.brandGradient)
                .shadow(color: Theme.ember.opacity(0.35), radius: size * 0.18, y: size * 0.06)
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Reusable branded page header.
struct BrandHeader: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
                    .frame(width: 46, height: 46)
                    .background(Theme.ember.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(18)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ember.opacity(0.15))
        )
    }
}

extension View {
    /// Soft branded background used behind windows.
    func brandBackground() -> some View {
        background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Theme.ember.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
                RadialGradient(colors: [Theme.gold.opacity(0.06), .clear], center: .bottomLeading, startRadius: 0, endRadius: 700)
            }
            .ignoresSafeArea()
        )
    }
}
