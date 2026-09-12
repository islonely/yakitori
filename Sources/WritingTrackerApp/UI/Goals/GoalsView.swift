import SwiftUI
import WritingTrackerCore

struct GoalsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isAdding = false

    private var goals: [GoalProgress] { state.container.statistics.goalProgress() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Goals", subtitle: "Daily, weekly and project targets", symbol: "target")
                HStack {
                    Spacer()
                    Button { isAdding = true } label: {
                        Label("New Goal", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if goals.isEmpty {
                    EmptyStateView(title: "No goals yet", message: "Set daily, weekly, monthly, or project goals to track your progress.", systemImage: "target")
                } else {
                    ForEach(goals) { progress in
                        goalRow(progress)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Goals")
        .sheet(isPresented: $isAdding) {
            GoalEditorView().environmentObject(state)
        }
    }

    private func goalRow(_ progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(progress.goal.period.displayName) \(progress.goal.metric.displayName.lowercased()) goal")
                        .font(.headline)
                    if let projectID = progress.goal.projectID,
                       let project = try? state.container.projects.project(id: projectID) {
                        Text(project.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    try? state.container.goals.delete(goalID: progress.goal.id)
                    state.refresh()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: min(1, progress.fraction))
            HStack {
                Text("\(Format.int(Int(progress.currentValue))) of \(Format.int(Int(progress.goal.target))) \(progress.goal.metric.unit)")
                    .font(.callout)
                Spacer()
                if progress.isComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                } else {
                    Text("\(Format.percent(progress.fraction))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }
}

struct GoalEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var period: GoalPeriod = .daily
    @State private var metric: GoalMetric = .words
    @State private var target = "500"
    @State private var projectID = ""

    private var projects: [Project] { (try? state.container.projects.allProjects()) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Goal").font(.title2.weight(.semibold))
            Form {
                Picker("Period", selection: $period) {
                    ForEach(GoalPeriod.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Metric", selection: $metric) {
                    ForEach(GoalMetric.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Target", text: $target)
                if period == .project || period == .deadline {
                    Picker("Project", selection: $projectID) {
                        Text("Select…").tag("")
                        ForEach(projects) { Text($0.title).tag($0.id) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(Double(target) == nil)
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
    }

    private func create() {
        guard let value = Double(target) else { return }
        do {
            try state.container.goals.createGoal(
                period: period,
                metric: metric,
                target: value,
                projectID: projectID.isEmpty ? nil : projectID
            )
            state.refresh()
            dismiss()
        } catch {
            state.presentError(error)
        }
    }
}
