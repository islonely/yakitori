import SwiftUI
import Charts
import WritingTrackerCore

enum ProjectSort: String, CaseIterable, Identifiable {
    case recent
    case wordCount
    case activity
    case completion
    case creation
    case alphabetical

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Recent"
        case .wordCount: return "Word count"
        case .activity: return "Activity"
        case .completion: return "Completion"
        case .creation: return "Creation date"
        case .alphabetical: return "Alphabetical"
        }
    }
}

enum ProjectFilter: String, CaseIterable, Identifiable {
    case all, active, completed, archived
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ProjectsView: View {
    @EnvironmentObject private var state: AppState
    @State private var sort: ProjectSort = .recent
    @State private var filter: ProjectFilter = .all
    @State private var isCreating = false

    private var projects: [Project] {
        var all = (try? state.container.projects.allProjects()) ?? []
        switch filter {
        case .all: all = all.filter { $0.status != .archived }
        case .active: all = all.filter { $0.status.isActive }
        case .completed: all = all.filter { $0.status.isCompleted }
        case .archived: all = all.filter { $0.status == .archived }
        }
        return sorted(all)
    }

    var body: some View {
        Group {
            if let projectID = state.selectedProjectID {
                ProjectDetailView(projectID: projectID)
                    .environmentObject(state)
            } else {
                library
            }
        }
        .sheet(isPresented: $isCreating) {
            ProjectEditorView(project: nil)
                .environmentObject(state)
        }
        .id(state.dataVersion)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects").font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(ProjectFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Picker("Sort", selection: $sort) {
                    ForEach(ProjectSort.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 150)
                Button {
                    isCreating = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)

            if projects.isEmpty {
                EmptyStateView(title: "No projects", message: "Create a project to associate your writing with a book, article, or thesis.", systemImage: "books.vertical")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)], spacing: 16) {
                        ForEach(projects) { project in
                            ProjectCard(project: project)
                                .onTapGesture { state.selectedProjectID = project.id }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func sorted(_ projects: [Project]) -> [Project] {
        switch sort {
        case .recent, .activity:
            return projects.sorted { lastActivity($0) > lastActivity($1) }
        case .wordCount:
            return projects.sorted { $0.currentWordCount > $1.currentWordCount }
        case .completion:
            return projects.sorted { ($0.progressFraction ?? 0) > ($1.progressFraction ?? 0) }
        case .creation:
            return projects.sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return projects.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func lastActivity(_ project: Project) -> Date {
        let sessions = (try? state.container.sessions.sessions(forProject: project.id)) ?? []
        return sessions.map(\.startedAt).max() ?? project.createdAt
    }
}

struct ProjectCard: View {
    @EnvironmentObject private var state: AppState
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(project.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let description = project.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(alignment: .center, spacing: 14) {
                ProgressRing(fraction: project.progressFraction ?? completionFallback, lineWidth: 7)
                    .scaleEffect(0.8, anchor: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Format.int(project.currentWordCount)) words").font(.subheadline)
                    if let target = project.targetWordCount {
                        Text("of \(Format.int(target))").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(project.status.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("Last active: \(lastActiveText)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(height: 170)
        .cardStyle()
        .contentShape(Rectangle())
    }

    private var completionFallback: Double {
        project.status.isCompleted ? 1 : 0
    }

    private var lastActiveText: String {
        let sessions = (try? state.container.sessions.sessions(forProject: project.id)) ?? []
        guard let last = sessions.map(\.startedAt).max() else { return "Never" }
        if Calendar.current.isDateInToday(last) { return "Today" }
        if Calendar.current.isDateInYesterday(last) { return "Yesterday" }
        return Format.shortDayYear.string(from: last)
    }
}

struct ProjectEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let project: Project?

    @State private var title = ""
    @State private var type: ProjectType = .novel
    @State private var status: ProjectStatus = .planning
    @State private var description = ""
    @State private var target = ""
    @State private var startingWords = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project == nil ? "New Project" : "Edit Project")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $type) {
                    ForEach(ProjectType.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Status", selection: $status) {
                    ForEach(ProjectStatus.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Description", text: $description, axis: .vertical)
                TextField("Target word count", text: $target)
                TextField("Starting word count", text: $startingWords)
                Toggle("Deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
        .onAppear(perform: load)
    }

    private func load() {
        guard let project else { return }
        title = project.title
        type = project.type
        status = project.status
        description = project.description ?? ""
        target = project.targetWordCount.map(String.init) ?? ""
        startingWords = String(project.startingWordCount)
        if let deadlineDate = project.deadline {
            hasDeadline = true
            deadline = deadlineDate
        }
    }

    private func save() {
        let targetValue = Int(target.trimmingCharacters(in: .whitespaces))
        let startingValue = Int(startingWords.trimmingCharacters(in: .whitespaces)) ?? 0
        do {
            if var existing = project {
                existing.title = title
                existing.type = type
                existing.status = status
                existing.description = description.isEmpty ? nil : description
                existing.targetWordCount = targetValue
                existing.startingWordCount = startingValue
                existing.deadline = hasDeadline ? deadline : nil
                try state.container.projects.update(existing)
            } else {
                try state.container.projects.createProject(
                    title: title,
                    type: type,
                    description: description.isEmpty ? nil : description,
                    targetWordCount: targetValue,
                    startingWordCount: startingValue,
                    deadline: hasDeadline ? deadline : nil
                )
            }
            state.refresh()
            dismiss()
        } catch {
            state.presentError(error)
        }
    }
}
