import SwiftUI
import WritingTrackerCore

struct SessionsView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter = SessionFilter()
    @State private var selection: String?
    @State private var editingSession: Session?
    @State private var isAddingManual = false

    private var statistics: StatisticsService { state.container.statistics }
    private var calendar: CalendarContext { statistics.calendar }

    private var sessions: [Session] {
        (try? state.container.sessions.sessions(filter: filter)) ?? []
    }

    private var projects: [Project] { (try? state.container.projects.allProjects()) ?? [] }
    private var applications: [WritingApplication] { (try? state.container.applicationRepository.all()) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
            Divider()
            if sessions.isEmpty {
                EmptyStateView(title: "No sessions found", message: "Adjust the filters, or start writing to record a session.", systemImage: "list.bullet.rectangle")
            } else {
                table
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingManual = true
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingSession) { session in
            SessionDetailView(session: session)
                .environmentObject(state)
        }
        .sheet(isPresented: $isAddingManual) {
            ManualEntryView().environmentObject(state)
        }
        .id(state.dataVersion)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes and types", text: Binding(
                get: { filter.searchText ?? "" },
                set: { filter.searchText = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 240)

            Picker("Project", selection: Binding(
                get: { filter.projectID ?? "all" },
                set: { filter.projectID = $0 == "all" ? nil : $0 }
            )) {
                Text("All projects").tag("all")
                ForEach(projects) { project in Text(project.title).tag(project.id) }
            }
            .frame(width: 170)

            Picker("Application", selection: Binding(
                get: { filter.applicationID ?? "all" },
                set: { filter.applicationID = $0 == "all" ? nil : $0 }
            )) {
                Text("All apps").tag("all")
                ForEach(applications) { app in Text(app.displayName).tag(app.id) }
            }
            .frame(width: 150)

            Picker("Type", selection: Binding(
                get: { filter.sessionType ?? SessionType.unknown },
                set: { filter.sessionType = $0 == .unknown ? nil : $0 }
            )) {
                Text("All types").tag(SessionType.unknown)
                ForEach(SessionType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(width: 130)

            Spacer()

            Button("Clear") { filter = SessionFilter() }
                .buttonStyle(.link)
                .opacity(filter == SessionFilter() ? 0 : 1)
        }
        .padding(12)
    }

    private var table: some View {
        let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        let appNames = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0.displayName) })
        return Table(sessions, selection: $selection) {
            TableColumn("Date") { session in
                Text(Format.shortDayYear.string(from: session.startedAt))
            }
            .width(min: 100, ideal: 120)
            TableColumn("Time") { session in
                Text(Format.timeRange(session.startedAt, session.endedAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Project") { session in
                Text(projectNames[session.projectID ?? ""] ?? "—")
            }
            TableColumn("Application") { session in
                Text(appNames[session.applicationID ?? ""] ?? "—")
            }
            TableColumn("Type") { session in
                Text(session.sessionType.displayName)
            }
            .width(min: 80, ideal: 90)
            TableColumn("Active") { session in
                Text(Format.duration(session.activeSeconds))
            }
            .width(min: 60, ideal: 70)
            TableColumn("Net") { session in
                Text(session.netWordChange.map { ($0 >= 0 ? "+" : "") + Format.int($0) } ?? "—")
                    .foregroundStyle((session.netWordChange ?? 0) < 0 ? .orange : .primary)
            }
            .width(min: 60, ideal: 70)
            TableColumn("WPM") { session in
                Text(session.wordsPerMinute.map { Format.decimal($0) } ?? "—")
            }
            .width(min: 50, ideal: 60)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let session = sessions.first(where: { $0.id == id }) {
                Button("Edit Session…") { editingSession = session }
            }
        } primaryAction: { ids in
            if let id = ids.first, let session = sessions.first(where: { $0.id == id }) {
                editingSession = session
            }
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var session: Session
    @State private var notes: String
    @State private var sessionType: SessionType
    @State private var projectID: String
    @State private var activeMinutes: Double
    @State private var confirmDelete = false

    init(session: Session) {
        _session = State(initialValue: session)
        _notes = State(initialValue: session.notes ?? "")
        _sessionType = State(initialValue: session.sessionType)
        _projectID = State(initialValue: session.projectID ?? "")
        _activeMinutes = State(initialValue: session.activeSeconds / 60)
    }

    private var projects: [Project] { (try? state.container.projects.allProjects()) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Session Detail").font(.title2.weight(.semibold))
            Text("\(Format.day.string(from: session.startedAt)) · \(Format.timeRange(session.startedAt, session.endedAt))")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("Project").foregroundStyle(.secondary)
                    Picker("", selection: $projectID) {
                        Text("Unassigned").tag("")
                        ForEach(projects) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Picker("", selection: $sessionType) {
                        ForEach(SessionType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Active minutes").foregroundStyle(.secondary)
                    TextField("", value: $activeMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Word counts").foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("Start \(session.startingWordCount.map(Format.int) ?? "—")")
                        Text("End \(session.endingWordCount.map(Format.int) ?? "—")")
                        Text("Net \(session.netWordChange.map { ($0 >= 0 ? "+" : "") + Format.int($0) } ?? "—")")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            }

            Spacer()

            HStack {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
        .alert("Delete this session?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the session and rebuilds daily statistics. This cannot be undone.")
        }
    }

    private func save() {
        var updated = session
        updated.notes = notes.isEmpty ? nil : notes
        updated.sessionType = sessionType
        updated.projectID = projectID.isEmpty ? nil : projectID
        updated.activeSeconds = max(0, activeMinutes * 60)
        if let ended = updated.endedAt {
            updated.endedAt = max(ended, updated.startedAt)
        }
        do {
            try state.container.sessions.updateSession(updated)
            state.refresh()
            dismiss()
        } catch {
            state.presentError(error)
        }
    }

    private func delete() {
        do {
            try state.container.sessions.deleteSession(id: session.id)
            state.refresh()
            dismiss()
        } catch {
            state.presentError(error)
        }
    }
}

struct ManualEntryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var projectID = ""
    @State private var date = Date()
    @State private var hours = 1
    @State private var minutes = 0
    @State private var words = "500"
    @State private var sessionType: SessionType = .drafting
    @State private var notes = ""

    private var projects: [Project] { (try? state.container.projects.allProjects()) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Manual Entry").font(.title2.weight(.semibold))
            Text("Record writing done on paper, on another computer, or offline.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                Picker("Project", selection: $projectID) {
                    Text("Unassigned").tag("")
                    ForEach(projects) { Text($0.title).tag($0.id) }
                }
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Stepper("Hours: \(hours)", value: $hours, in: 0...24)
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                }
                TextField("Net words", text: $words)
                Picker("Type", selection: $sessionType) {
                    ForEach(SessionType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(Int(words) == nil && words != "-")
            }
        }
        .padding(24)
        .frame(width: 460, height: 430)
    }

    private func save() {
        let totalSeconds = Double(hours * 3600 + minutes * 60)
        let wordCount = Int(words.trimmingCharacters(in: .whitespaces)) ?? 0
        do {
            try state.container.sessions.addManualSession(
                projectID: projectID.isEmpty ? nil : projectID,
                date: date,
                words: wordCount,
                activeSeconds: totalSeconds,
                sessionType: sessionType,
                notes: notes.isEmpty ? nil : notes
            )
            state.refresh()
            dismiss()
        } catch {
            state.presentError(error)
        }
    }
}
