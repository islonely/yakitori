import SwiftUI
import AppKit
import WritingTrackerCore

struct MenuBarLabel: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var tracking: TrackingModel

    var body: some View {
        if state.settings.menuBarShowsWordCount {
            Label {
                Text(Format.compact(tracking.snapshot.todayNetWords))
            } icon: {
                Image(systemName: "square.and.pencil")
            }
        } else {
            Image(systemName: "square.and.pencil")
        }
    }
}

struct MenuBarPopover: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var tracking: TrackingModel
    @Environment(\.openWindow) private var openWindow

    private var statistics: StatisticsService { state.container.statistics }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            todaySection
            Divider()
            sessionSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(Color.accentColor)
            Text("Writing Tracker")
                .font(.headline)
            Spacer()
            Circle()
                .fill(tracking.snapshot.isSessionOpen ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                stat(value: Format.int(tracking.snapshot.todayNetWords), label: "words")
                stat(value: Format.duration(tracking.snapshot.todayActiveSeconds), label: "active")
                stat(value: "\(tracking.snapshot.todaySessions)", label: "sessions")
            }
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(streak) day streak").font(.callout)
            }
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = state.currentProject {
                Text("Current Project").font(.caption).foregroundStyle(.secondary)
                Text(project.title).font(.subheadline.weight(.medium))
            }
            if tracking.snapshot.isSessionOpen {
                HStack {
                    Text(sessionStateText).font(.callout)
                    Spacer()
                    if let net = tracking.snapshot.currentSessionNetWords {
                        Text("\(net >= 0 ? "+" : "")\(Format.int(net)) net")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    if tracking.snapshot.state == .paused {
                        Button("Resume") { state.resumeSession() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pause") { state.pauseSession() }
                            .buttonStyle(.bordered)
                    }
                    Button("Stop") { state.stopSession() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
            } else {
                sessionStartControls
            }
        }
    }

    private var sessionStartControls: some View {
        HStack(spacing: 8) {
            Button {
                state.startManualSession(projectID: state.settings.currentProjectID, type: state.settings.defaultSessionType)
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            Picker("", selection: Binding(
                get: { state.settings.defaultSessionType },
                set: { newValue in state.updateSettings { $0.defaultSessionType = newValue } }
            )) {
                ForEach([SessionType.drafting, .editing, .revising, .proofreading, .research, .planning, .other], id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Dashboard", systemImage: "rectangle.on.rectangle")
            }
            Spacer()
            Button {
                openWindow(id: "dashboard")
                state.selectedSection = .settings
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Writing Tracker")
        }
        .buttonStyle(.bordered)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var sessionStateText: String {
        if let started = tracking.snapshot.currentSessionStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            switch tracking.snapshot.state {
            case .paused: return "Paused · \(Format.duration(elapsed))"
            default: return "Active · \(Format.duration(elapsed))"
            }
        }
        return tracking.snapshot.state.rawValue.capitalized
    }

    private var streak: Int {
        statistics.streakStatistics().currentStreak
    }
}
