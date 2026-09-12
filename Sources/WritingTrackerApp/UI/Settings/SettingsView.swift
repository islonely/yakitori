import SwiftUI
import AppKit
import WritingTrackerCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    private func binding<T>(_ keyPath: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { newValue in state.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(.largeTitle.weight(.semibold))
                generalSection
                trackingSection
                applicationsSection
                scheduleSection
                goalsSection
                notificationsSection
                privacySection
                PermissionCenterView()
                dataSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Settings")
        .id(state.dataVersion)
    }

    // MARK: - Sections

    private var generalSection: some View {
        settingsCard("General") {
            Toggle("Launch at Login", isOn: binding(\.launchAtLogin))
                .onChange(of: state.settings.launchAtLogin) { newValue in
                    state.container.permissionProvider.request(.launchAtLogin)
                    state.updateSettings { $0.launchAtLogin = newValue }
                }
            Toggle("Start tracking at launch", isOn: binding(\.startTrackingAtLaunch))
            Toggle("Show word count in menu bar", isOn: binding(\.menuBarShowsWordCount))
            Picker("Appearance", selection: binding(\.appearance)) {
                ForEach(AppAppearance.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var trackingSection: some View {
        settingsCard("Tracking") {
            Picker("Tracking mode", selection: binding(\.trackingMode)) {
                ForEach(TrackingMode.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Inactivity timeout", selection: binding(\.inactivityTimeout)) {
                ForEach(InactivityTimeout.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Default session type", selection: binding(\.defaultSessionType)) {
                ForEach(SessionType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Automatically match documents to projects", isOn: binding(\.automaticProjectMatching))
            HStack {
                Text("Status")
                Spacer()
                Text(state.tracking.isSessionOpen ? "Tracking" : "Idle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var applicationsSection: some View {
        let apps = (try? state.container.applicationRepository.all()) ?? []
        let wordState = state.permissionStatus(for: .wordAutomation)
        return settingsCard("Applications") {
            if apps.isEmpty {
                Text("No writing applications detected yet.").foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { app.enabled },
                                set: { newValue in updateApplication(app) { $0.enabled = newValue } }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.displayName).font(.body)
                                    Text("\(app.bundleIdentifier) · \(app.adapterType.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if app.adapterType == .word {
                                PermissionBadge(state: wordState)
                            }
                        }
                        Text(capabilitiesText(app))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            Button("Refresh detected applications") {
                seedApplications()
            }
        }
    }

    private var scheduleSection: some View {
        settingsCard("Writing schedule", subtitle: "Days off do not break your streak") {
            ForEach(weekdayOrder(), id: \.self) { weekday in
                let schedule = state.settings.writingSchedule.first { $0.weekday == weekday }
                Toggle(weekdayName(weekday), isOn: Binding(
                    get: { schedule?.enabled ?? true },
                    set: { newValue in
                        state.updateSettings { settings in
                            if let index = settings.writingSchedule.firstIndex(where: { $0.weekday == weekday }) {
                                settings.writingSchedule[index].enabled = newValue
                            } else {
                                settings.writingSchedule.append(WritingSchedule(weekday: weekday, enabled: newValue))
                            }
                        }
                    }
                ))
            }
        }
    }

    private var goalsSection: some View {
        settingsCard("Streaks") {
            Picker("Streak requirement", selection: binding(\.streakThresholdKind)) {
                ForEach(StreakThresholdKind.allCases) { Text($0.displayName).tag($0) }
            }
            if state.settings.streakThresholdKind == .custom {
                TextField("Custom words", value: binding(\.streakCustomWords), format: .number)
            }
            Picker("Week starts on", selection: binding(\.weekStart)) {
                ForEach(WeekStart.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var notificationsSection: some View {
        settingsCard("Notifications") {
            Toggle("Enable notifications", isOn: Binding(
                get: { state.settings.notificationsEnabled },
                set: { newValue in
                    state.updateSettings { $0.notificationsEnabled = newValue }
                    if newValue { state.requestPermission(.notifications) }
                }
            ))
            Toggle("Goal reminders", isOn: binding(\.notifyOnGoals)).disabled(!state.settings.notificationsEnabled)
            Toggle("Streak reminders", isOn: binding(\.notifyOnStreaks)).disabled(!state.settings.notificationsEnabled)
            Toggle("Milestone completions", isOn: binding(\.notifyOnMilestones)).disabled(!state.settings.notificationsEnabled)
        }
    }

    private var privacySection: some View {
        settingsCard("Privacy", subtitle: "Writing Tracker tracks activity, not content") {
            privacyRow("Manuscript text", "Never stored")
            privacyRow("Keyboard contents", "Never stored")
            privacyRow("Clipboard", "Not accessed")
            privacyRow("Screenshots", "Not taken")
            privacyRow("Cloud sync", "Disabled")
            privacyRow("Analytics", "Local only")
            Toggle("Enable optional diagnostics", isOn: binding(\.diagnosticsEnabled))
            Text("Diagnostics, when enabled, never include document names, paths, or manuscript text.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var dataSection: some View {
        settingsCard("Data") {
            HStack {
                Button("Export CSV…") { export(.csv) }
                Button("Export JSON…") { export(.json) }
                Button("Backup Database") { createBackup() }
            }
            Button("Rebuild Daily Aggregates") {
                let count = state.container.dataManagement.rebuildAggregates()
                state.alertMessage = "Rebuilt \(count) daily aggregates from session records."
                state.refresh()
            }
            backupsList
            Divider()
            Button(role: .destructive) {
                confirm(.deleteHistory)
            } label: {
                Text("Delete Session History…")
            }
            Button(role: .destructive) {
                confirm(.factoryReset)
            } label: {
                Text("Factory Reset…")
            }
            Text("Every destructive action creates a verified local backup first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert(item: $pendingConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .destructive(Text(confirmation.button)) { perform(confirmation) },
                secondaryButton: .cancel()
            )
        }
    }

    @State private var pendingConfirmation: Confirmation?

    enum Confirmation: Identifiable {
        case deleteHistory
        case factoryReset
        var id: String { title }
        var title: String {
            switch self {
            case .deleteHistory: return "Delete all session history?"
            case .factoryReset: return "Factory reset?"
            }
        }
        var message: String {
            switch self {
            case .deleteHistory: return "All sessions, events, and word-count snapshots will be removed. A backup is created first."
            case .factoryReset: return "All projects, sessions, goals, applications, and settings will be removed. A backup is created first."
            }
        }
        var button: String {
            switch self {
            case .deleteHistory: return "Delete History"
            case .factoryReset: return "Factory Reset"
            }
        }
    }

    private var backupsList: some View {
        let backups = state.container.backup.listBackups()
        return Group {
            if !backups.isEmpty {
                DisclosureGroup("Backups (\(backups.count))") {
                    ForEach(backups.prefix(10)) { backup in
                        HStack {
                            Text(backup.url.lastPathComponent).font(.caption).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(backup.byteSize), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([backup.url])
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func privacyRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func capabilitiesText(_ app: WritingApplication) -> String {
        let adapter = AdapterRegistry.shared.adapter(forBundleIdentifier: app.bundleIdentifier, adapterType: app.adapterType)
        let c = adapter.capabilities
        var parts: [String] = []
        parts.append(c.activeDocument ? "Document detection" : "Activity tracking")
        parts.append(c.wordCount ? "Word count" : "Word count unavailable")
        var flags: [String] = []
        if c.documentPath { flags.append("paths") }
        if c.projectDetection { flags.append("project detection") }
        if c.changeDetection { flags.append("change detection") }
        if !flags.isEmpty { parts.append("(" + flags.joined(separator: ", ") + ")") }
        return parts.joined(separator: " · ")
    }

    private func updateApplication(_ app: WritingApplication, mutate: (inout WritingApplication) -> Void) {
        var copy = app
        mutate(&copy)
        copy.updatedAt = Date()
        try? state.container.applicationRepository.update(copy)
        state.refresh()
    }

    private func seedApplications() {
        let detected = AdapterRegistry.shared.detectedApplications()
        for item in detected {
            if let existing = try? state.container.applicationRepository.find(bundleIdentifier: item.bundleIdentifier) {
                _ = existing
                continue
            }
            let record = WritingApplication(
                bundleIdentifier: item.bundleIdentifier,
                displayName: item.displayName,
                adapterType: item.adapterType
            )
            try? state.container.applicationRepository.insert(record)
        }
        state.refresh()
    }

    private func weekdayOrder() -> [Int] {
        state.settings.weekStart == .sunday ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6, 7, 1]
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[weekday - 1]
    }

    private func export(_ format: ExportFormat) {
        do {
            let result = try state.container.export.export(scope: .all, format: format)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = result.suggestedFileName
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try result.data.write(to: url, options: .atomic)
                state.alertMessage = "Exported to \(url.lastPathComponent)."
            }
        } catch {
            state.presentError(error)
        }
    }

    private func createBackup() {
        do {
            let url = try state.container.backup.createBackup(label: "manual")
            state.alertMessage = "Backup created: \(url.lastPathComponent)"
            state.refresh()
        } catch {
            state.presentError(error)
        }
    }

    private func confirm(_ confirmation: Confirmation) {
        pendingConfirmation = confirmation
    }

    private func perform(_ confirmation: Confirmation) {
        do {
            switch confirmation {
            case .deleteHistory:
                let url = try state.container.dataManagement.deleteSessionHistory()
                state.alertMessage = "Session history deleted. Backup: \(url.lastPathComponent)"
            case .factoryReset:
                let url = try state.container.dataManagement.factoryReset()
                state.alertMessage = "Factory reset complete. Backup: \(url.lastPathComponent)"
                state.updateSettings { $0.onboardingCompleted = false }
                state.isOnboardingPresented = true
            }
            state.refresh()
        } catch {
            state.presentError(error)
        }
    }
}
