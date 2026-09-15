import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
                BrandHeader(title: "Settings", subtitle: "Tracking, applications and privacy", symbol: "gearshape")
                generalSection
                trackingSection
                applicationsSection
                scheduleSection
                goalsSection
                notificationsSection
                communitySection
                privacySection
                PermissionCenterView()
                dataSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Settings")
    }

    // MARK: - Sections

    private var generalSection: some View {
        settingsCard("General") {
            Toggle("Launch at Login", isOn: Binding(
                get: { state.settings.launchAtLogin },
                set: { newValue in
                    state.container.permissionProvider.setLaunchAtLogin(newValue)
                    state.updateSettings { $0.launchAtLogin = newValue }
                }
            ))
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
            HotkeyRecorder()
            HStack {
                Text("Status")
                Spacer()
                TrackingStatusLabel()
            }
        }
    }

    private var applicationsSection: some View {
        let apps = ((try? state.container.applicationRepository.all()) ?? [])
            .sorted { lhs, rhs in
                let l = appSupportsWordCount(lhs), r = appSupportsWordCount(rhs)
                if l != r { return l }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        let wordState = state.permissionStatus(for: .wordAutomation)
        return settingsCard(
            "Applications",
            subtitle: "Word and Pages provide exact word counts. Everything else is tracked for time and focus only."
        ) {
            if apps.isEmpty {
                Text("No applications added yet.").foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { app.enabled },
                                set: { newValue in updateApplication(app) { $0.enabled = newValue } }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(app.displayName).font(.body)
                                        capabilityCapsule(app)
                                    }
                                    Text("\(app.bundleIdentifier) · \(app.adapterType.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if appSupportsWordCount(app) {
                                PermissionBadge(state: wordState)
                            }
                            Button {
                                removeApplication(app)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this application")
                        }
                        Text(capabilitiesText(app))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            HStack {
                Button {
                    addCustomApplication()
                } label: {
                    Label("Add Application…", systemImage: "plus")
                }
                Button("Refresh detected applications") {
                    seedApplications()
                }
            }
            Text("Any app can be added and tracked for time and focus. Exact word-count support is limited to Microsoft Word and Apple Pages.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func appSupportsWordCount(_ app: WritingApplication) -> Bool {
        app.adapterType == .word || app.adapterType == .pages
    }

    private func capabilityCapsule(_ app: WritingApplication) -> some View {
        let supported = appSupportsWordCount(app)
        return Text(supported ? "Word count" : "Time only")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((supported ? Theme.accent : Color.secondary).opacity(0.15))
            .foregroundStyle(supported ? Theme.accent : Color.secondary)
            .clipShape(Capsule())
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

    private var communitySection: some View {
        settingsCard("Community", subtitle: "Optional leaderboards and sharing") {
            TextField("Display name", text: Binding(
                get: { state.settings.communityDisplayName ?? "" },
                set: { newValue in
                    state.updateSettings { $0.communityDisplayName = newValue.isEmpty ? nil : newValue }
                }
            ))
            Toggle("Publish my stats to leaderboards", isOn: Binding(
                get: { state.settings.publishStatsEnabled },
                set: { newValue in
                    state.updateSettings { $0.publishStatsEnabled = newValue }
                    if newValue {
                        state.publishCommunityStats()
                    } else {
                        state.unpublishCommunityStats()
                    }
                }
            ))
            Text("Only aggregate numbers are shared (words, active time, streaks, sessions, writing days). Documents, project names, paths, and manuscript text are never shared.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show sample leaderboard entries", isOn: binding(\.showSampleCommunity))
            Text("Placeholder entries so you can see the leaderboard layout. They disappear once a real community service is connected.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal Community Data") {
                    let url = state.container.dataDirectory
                        .appendingPathComponent("community.json")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? Data("{}".utf8).write(to: url)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Open Community") {
                    state.selectedSection = .community
                }
                .buttonStyle(.link)
            }
        }
    }

    private var privacySection: some View {
        settingsCard("Privacy", subtitle: "See the Privacy tab for the full explanation") {
            Toggle("Enable optional diagnostics", isOn: binding(\.diagnosticsEnabled))
            Text("Diagnostics never include document names, paths, manuscript text, or typed characters.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Privacy & Permissions") {
                state.selectedSection = .privacy
            }
            .buttonStyle(.link)
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

    /// Lets the user add any installed application, even one not on the built-in
    /// list. Unknown apps use the generic focus/activity adapter.
    private func addCustomApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose a writing application to track."
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            state.alertMessage = "That item is not a valid application bundle."
            return
        }

        if let existing = try? state.container.applicationRepository.find(bundleIdentifier: bundleID) {
            var updated = existing
            updated.enabled = true
            updated.automaticTrackingEnabled = true
            updated.updatedAt = Date()
            try? state.container.applicationRepository.update(updated)
            selectApplication(existing.id)
            state.refresh()
            return
        }

        let displayName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let app = WritingApplication(
            bundleIdentifier: bundleID,
            displayName: displayName,
            adapterType: AdapterRegistry.defaultAdapterType(forBundleIdentifier: bundleID),
            category: .writing,
            enabled: true,
            automaticTrackingEnabled: true
        )
        try? state.container.applicationRepository.insert(app)
        selectApplication(app.id)
        state.refresh()
    }

    private func removeApplication(_ app: WritingApplication) {
        try? state.container.applicationRepository.delete(id: app.id)
        state.updateSettings { settings in
            settings.selectedApplicationIDs.removeAll { $0 == app.id }
        }
        state.refresh()
    }

    private func selectApplication(_ id: String) {
        state.updateSettings { settings in
            if !settings.selectedApplicationIDs.contains(id) {
                settings.selectedApplicationIDs.append(id)
            }
        }
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
