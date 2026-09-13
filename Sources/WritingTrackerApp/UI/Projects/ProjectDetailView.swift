import SwiftUI
import Charts
import AppKit
import WritingTrackerCore

struct ProjectDetailView: View {
    @EnvironmentObject private var state: AppState
    let projectID: String

    @State private var project: Project?
    @State private var stats: ProjectStatistics?
    @State private var milestones: [Milestone] = []
    @State private var rules: [AssociationRule] = []
    @State private var sessions: [Session] = []
    @State private var isEditing = false
    @State private var newMilestone = ""
    @State private var newRuleValue = ""
    @State private var newRuleType: AssociationRule.RuleType = .folderPath
    @State private var confirmDelete = false

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    var body: some View {
        ScrollView {
            if let project, let stats {
                VStack(alignment: .leading, spacing: 20) {
                    header(project)
                    progressCards(project, stats)
                    statsGrid(stats)
                    projections(stats)
                    charts(project)
                    milestonesSection
                    rulesSection
                    sessionsSection
                    dangerZone(project)
                }
                .padding(24)
            } else {
                EmptyStateView(title: "Project not found", message: "This project may have been deleted.", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(project?.title ?? "Project")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    state.selectedProjectID = nil
                } label: {
                    Label("All Projects", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let project {
                ProjectEditorView(project: project).environmentObject(state)
            }
        }
        .alert("Delete this project?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A backup is created first. The project, its documents, and its session links are removed.")
        }
        .onAppear(perform: load)
        .onChange(of: state.dataVersion) { _ in load() }
    }

    private func header(_ project: Project) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.title).font(.largeTitle.weight(.semibold))
                    if state.settings.currentProjectID == project.id {
                        Text("CURRENT")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(project.type.displayName)
                    Text("·")
                    Text(project.status.displayName)
                    if let deadline = project.deadline {
                        Text("·")
                        Text("Due \(Format.shortDayYear.string(from: deadline))")
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if state.settings.currentProjectID != project.id {
                Button {
                    state.setCurrentProject(project.id)
                } label: {
                    Label("Set as Current", systemImage: "target")
                }
            }
        }
    }

    private func progressCards(_ project: Project, _ stats: ProjectStatistics) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                ProgressRing(fraction: project.progressFraction ?? 0, lineWidth: 12)
                Text("\(Format.int(project.currentWordCount)) / \(project.targetWordCount.map(Format.int) ?? "—")")
                    .font(.callout)
                if let remaining = stats.wordsRemaining {
                    Text("\(Format.int(remaining)) remaining").font(.caption).foregroundStyle(.secondary)
                }
            }
            .cardStyle()
            .frame(width: 220)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Started", value: project.startedAt.map { Format.shortDayYear.string(from: $0) } ?? "—")
                MetricTile(title: "Last activity", value: stats.lastActivity.map { Format.shortDayYear.string(from: $0) } ?? "—")
                MetricTile(title: "Active time", value: Format.duration(stats.totalActiveSeconds))
                MetricTile(title: "Sessions", value: Format.int(stats.sessionCount))
                MetricTile(title: "Writing days", value: Format.int(stats.writingDays))
                MetricTile(title: "Avg / day", value: Format.int(Int(stats.averageWordsPerDay.rounded())))
                MetricTile(title: "Avg / session", value: Format.int(Int(stats.averageWordsPerSession.rounded())))
                MetricTile(title: "Words / hour", value: stats.wordsPerHour.map { Format.int(Int($0.rounded())) } ?? "—")
                MetricTile(title: "Net words", value: Format.int(stats.netWords))
            }
        }
    }

    private func statsGrid(_ stats: ProjectStatistics) -> some View {
        EmptyView()
    }

    private func projections(_ stats: ProjectStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Projected completion", subtitle: "Estimates based on recent pace")
            if stats.projections.isEmpty {
                Text("Set a target word count to see projections.").foregroundStyle(.secondary)
            } else {
                ForEach(stats.projections, id: \.label) { projection in
                    HStack {
                        Text(projection.label).foregroundStyle(.secondary)
                        Spacer()
                        if projection.isSufficient, let date = projection.projectedDate {
                            Text("\(Format.shortDayYear.string(from: date))")
                            Text("· \(projection.daysRemaining ?? 0) days")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not enough data").foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                Text("Projections are estimates, not guarantees.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func charts(_ project: Project) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                projectionChart(project)
                burnDownChart(project)
            }
            HStack(alignment: .top, spacing: 16) {
                documentChart
                dailyChart
            }
        }
    }

    private func projectionChart(_ project: Project) -> some View {
        let cumulative = statistics.cumulativeProjectSeries(projectID: project.id)
        let projections = stats?.projections ?? []
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cumulative progress", subtitle: "With pace projections")
            if cumulative.count < 2 {
                Text("No word-count history yet.").foregroundStyle(.secondary).frame(height: 200)
            } else {
                ProjectionConeChart(cumulative: cumulative, target: project.targetWordCount, projections: projections)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func burnDownChart(_ project: Project) -> some View {
        let cumulative = statistics.cumulativeProjectSeries(projectID: project.id)
        let required = statistics.deadlinePaceSeries(projectID: project.id)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Burn-down", subtitle: "Remaining words vs required pace")
            if let target = project.targetWordCount, cumulative.count >= 2, !required.isEmpty {
                BurnDownChart(cumulative: cumulative, target: target, required: required)
            } else {
                Text("Set a target and deadline to see this chart.").foregroundStyle(.secondary).frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var documentChart: some View {
        let series = statistics.documentWordCountSeries(projectID: projectID)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By document")
            if series.isEmpty {
                Text("No per-document history yet.").foregroundStyle(.secondary).frame(height: 200)
            } else {
                DocumentWordCountChart(series: series)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var dailyChart: some View {
        let daily = projectDailyStats()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily output")
            if daily.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary).frame(height: 180)
            } else {
                Chart(daily, id: \.date) { point in
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Words", point.words))
                        .foregroundStyle(Theme.accent.gradient)
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Milestones")
            if let project {
                MilestoneTimeline(
                    project: project,
                    milestones: milestones,
                    projectedCompletion: stats?.projections.compactMap(\.projectedDate).min()
                )
                Divider()
            }
            if milestones.isEmpty {
                Text("No milestones yet.").foregroundStyle(.secondary)
            } else {
                ForEach(milestones) { milestone in
                    HStack {
                        Button {
                            toggleMilestone(milestone)
                        } label: {
                            Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(milestone.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        Text(milestone.title)
                            .strikethrough(milestone.isCompleted)
                        if let target = milestone.targetValue {
                            Text("\(Int(target).formatted())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let completed = milestone.completedAt {
                            Text(Format.shortDay.string(from: completed))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            try? state.container.projects.deleteMilestone(id: milestone.id)
                            load()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                }
            }
            HStack {
                TextField("Add milestone", text: $newMilestone)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addMilestone() }
                    .disabled(newMilestone.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Automatic association rules", subtitle: "Assign documents to this project by path or name")
            ForEach(rules) { rule in
                HStack {
                    Text(rule.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    Text(rule.value).font(.callout).lineLimit(1)
                    Spacer()
                    Button {
                        try? state.container.projects.deleteRule(id: rule.id)
                        load()
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            HStack {
                Picker("", selection: $newRuleType) {
                    Text("Folder contains").tag(AssociationRule.RuleType.folderPath)
                    Text("Exact file").tag(AssociationRule.RuleType.filePath)
                    Text("Document name").tag(AssociationRule.RuleType.documentName)
                }
                .labelsHidden()
                .frame(width: 160)
                TextField("Value", text: $newRuleValue)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addRule() }
                    .disabled(newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button {
                chooseFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }
            Text("Choosing a folder grants access only to that folder and creates a matching rule.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent sessions")
            if sessions.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(8)) { session in
                    HStack {
                        Text(Format.shortDayYear.string(from: session.startedAt))
                        Text(Format.timeRange(session.startedAt, session.endedAt)).foregroundStyle(.secondary)
                        Text(session.sessionType.displayName).foregroundStyle(.secondary)
                        Spacer()
                        Text(session.netWordChange.map { ($0 >= 0 ? "+" : "") + Format.int($0) } ?? "—")
                            .monospacedDigit()
                        Text(Format.duration(session.activeSeconds)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func dangerZone(_ project: Project) -> some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
            Spacer()
        }
    }

    // MARK: - Data

    private func load() {
        project = try? state.container.projects.project(id: projectID)
        if project != nil {
            stats = try? statistics.projectStatistics(projectID: projectID)
            state.container.statistics.refreshSettings()
        }
        milestones = (try? state.container.projects.milestones(forProject: projectID)) ?? []
        rules = (try? state.container.projects.rules(forProject: projectID)) ?? []
        sessions = (try? state.container.sessions.sessions(forProject: projectID)) ?? []
    }

    private func addMilestone() {
        let title = newMilestone.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        _ = try? state.container.projects.addMilestone(projectID: projectID, title: title, targetValue: nil, metric: nil)
        newMilestone = ""
        load()
    }

    private func toggleMilestone(_ milestone: Milestone) {
        if milestone.isCompleted {
            try? state.container.projects.reopenMilestone(id: milestone.id)
        } else {
            try? state.container.projects.completeMilestone(id: milestone.id)
            state.container.notifications.notifyMilestone(milestone)
        }
        load()
    }

    private func addRule() {
        let value = newRuleValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        _ = try? state.container.projects.addRule(projectID: projectID, type: newRuleType, value: value)
        state.container.association.reload()
        newRuleValue = ""
        load()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder whose documents should belong to this project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = FileAccessBookmarkStore.shared.add(url: url)
        _ = try? state.container.projects.addRule(projectID: projectID, type: .folderPath, value: url.path)
        state.container.association.reload()
        state.container.permissionProvider.refresh()
        state.refreshPermissions()
        load()
    }

    private func deleteProject() {
        do {
            try state.container.dataManagement.deleteProject(projectID: projectID)
            state.selectedProjectID = nil
            state.refresh()
        } catch {
            state.presentError(error)
        }
    }

    private func cumulativePoints(_ project: Project) -> [(date: Date, words: Int)] {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        var running = project.startingWordCount
        var points: [(Date, Int)] = [(project.createdAt, running)]
        for session in sorted {
            if let ending = session.endingWordCount {
                running = ending
                points.append((session.endedAt ?? session.startedAt, running))
            } else if let net = session.netWordChange {
                running += net
                points.append((session.endedAt ?? session.startedAt, running))
            }
        }
        return points.map { (date: $0.0, words: $0.1) }
    }

    private func projectDailyStats() -> [(date: Date, words: Int)] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.map { (date: $0.key, words: $0.value.reduce(0) { $0 + ($1.netWordChange ?? 0) }) }
            .map { (date: $0.date, words: $0.words) }
            .sorted { $0.date < $1.date }
    }
}

private extension AssociationRule.RuleType {
    var displayName: String {
        switch self {
        case .folderPath: return "Folder"
        case .filePath: return "File"
        case .documentName: return "Name"
        case .applicationProject: return "App"
        }
    }
}
