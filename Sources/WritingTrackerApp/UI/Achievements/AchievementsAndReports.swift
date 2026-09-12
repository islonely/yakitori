import SwiftUI
import WritingTrackerCore

struct AchievementsView: View {
    @EnvironmentObject private var state: AppState

    private var achievements: [Achievement] { state.container.reports.achievements() }
    private var unlocked: Int { achievements.filter(\.isUnlocked).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(
                    title: "Achievements",
                    subtitle: "\(unlocked) of \(achievements.count) unlocked",
                    symbol: "trophy"
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)], spacing: 16) {
                    ForEach(achievements) { achievement in
                        achievementCard(achievement)
                    }
                }
                Text("Achievements are optional and never used to judge your progress. They simply mark milestones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Achievements")
    }

    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: achievement.symbol)
                    .font(.title2)
                    .foregroundStyle(achievement.isUnlocked ? Theme.accent : .secondary)
                Spacer()
                if achievement.isUnlocked {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            Text(achievement.title).font(.headline)
            Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: achievement.progress)
        }
        .cardStyle()
        .opacity(achievement.isUnlocked ? 1 : 0.75)
    }
}

struct ReportsView: View {
    @EnvironmentObject private var state: AppState

    enum Kind: String, CaseIterable, Identifiable {
        case weekly, monthly, yearly, yearInReview, comparison
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .yearInReview: return "Year in Review"
            case .comparison: return "Compare"
            }
        }
    }

    @State private var kind: Kind = .weekly
    @State private var referenceDate = Date()
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var firstProject = ""
    @State private var secondProject = ""

    private var reports: ReportService { state.container.reports }
    private var projects: [Project] { (try? state.container.projects.allProjects()) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Reports", subtitle: "Weekly, monthly and yearly summaries", symbol: "doc.text")
                HStack {
                    Spacer()
                    Picker("Report", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 180)
                }
                controls
                reportContent
            }
            .padding(24)
        }
        .navigationTitle("Reports")
        .onChange(of: kind) { _ in }
    }

    @ViewBuilder
    private var controls: some View {
        switch kind {
        case .weekly, .monthly:
            DatePicker("Reference date", selection: $referenceDate, displayedComponents: .date)
        case .yearly, .yearInReview:
            Stepper("Year: \(year)", value: $year, in: 2000...2100)
        case .comparison:
            HStack {
                Picker("Project A", selection: $firstProject) {
                    Text("Select…").tag("")
                    ForEach(projects) { Text($0.title).tag($0.id) }
                }
                Picker("Project B", selection: $secondProject) {
                    Text("Select…").tag("")
                    ForEach(projects) { Text($0.title).tag($0.id) }
                }
            }
            .frame(maxWidth: 520)
        }
    }

    @ViewBuilder
    private var reportContent: some View {
        switch kind {
        case .weekly:
            reportCard(reports.weeklyReport(containing: referenceDate))
        case .monthly:
            reportCard(reports.monthlyReport(containing: referenceDate))
        case .yearly:
            reportCard(reports.yearlyReport(year: year))
        case .yearInReview:
            yearInReviewCard(reports.yearInReview(year: year))
        case .comparison:
            comparisonCard
        }
    }

    private func reportCard(_ report: WritingReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: report.title, subtitle: report.subtitle)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Net words", value: Format.int(report.period.netWords))
                MetricTile(title: "Active time", value: Format.duration(report.period.activeSeconds))
                MetricTile(title: "Sessions", value: "\(report.period.sessions)")
                MetricTile(title: "Writing days", value: "\(report.period.writingDays)")
                MetricTile(title: "Average/day", value: Format.int(Int(report.period.averageWordsPerDay.rounded())))
                MetricTile(title: "Best day", value: report.period.bestDay.map { Format.int($0.words) } ?? "—")
            }
        }
        .cardStyle()
    }

    private func yearInReviewCard(_ report: WritingReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(report.title).font(.title.weight(.bold))
            ForEach(report.highlights, id: \.self) { highlight in
                Text(highlight).font(.title3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var comparisonCard: some View {
        if firstProject.isEmpty || secondProject.isEmpty || firstProject == secondProject {
            Text("Choose two different projects to compare.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        } else if let a = projects.first(where: { $0.id == firstProject }),
                  let b = projects.first(where: { $0.id == secondProject }),
                  let comparisons = try? reports.projectComparison(a, b) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "\(a.title) vs \(b.title)")
                ForEach(comparisons) { comparison in
                    HStack {
                        Text(comparison.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatNumber(comparison.current, isTime: comparison.label.contains("time"))).frame(width: 100, alignment: .trailing)
                        Text(formatNumber(comparison.previous, isTime: comparison.label.contains("time"))).frame(width: 100, alignment: .trailing).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    Divider()
                }
            }
            .cardStyle()
        } else {
            EmptyView()
        }
    }

    private func formatNumber(_ value: Double, isTime: Bool) -> String {
        isTime ? Format.duration(value) : Format.int(Int(value.rounded()))
    }
}
