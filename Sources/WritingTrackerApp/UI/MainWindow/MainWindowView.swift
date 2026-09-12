import SwiftUI
import AppKit
import WritingTrackerCore

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader
                List(selection: $state.selectedSection) {
                    Section {
                        ForEach([SidebarSection.dashboard, .statistics, .calendar, .sessions]) { section in
                            sidebarRow(section)
                        }
                    }
                    Section("Projects") {
                        sidebarRow(.projects)
                    }
                    Section {
                        ForEach([SidebarSection.goals, .reports, .achievements, .community]) { section in
                            sidebarRow(section)
                        }
                    }
                    Section {
                        ForEach([SidebarSection.settings, .privacy]) { section in
                            sidebarRow(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.sidebarGradient)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .brandBackground()
        }
        .sheet(isPresented: $state.isOnboardingPresented) {
            OnboardingView()
                .environmentObject(state)
        }
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .onAppear {
            // Show the dashboard like a normal app: dock icon, app menu bar.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // When the dashboard closes, return to a pure menu bar utility.
            // Tracking continues because the process stays alive.
            NSApp.setActivationPolicy(.accessory)
        }
        .alert("Yakitori", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            YakitoriMark(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Yakitori")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("writing tracker")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selectedSection {
        case .dashboard: DashboardView()
        case .statistics: StatisticsView()
        case .calendar: CalendarView()
        case .sessions: SessionsView()
        case .projects: ProjectsView()
        case .goals: GoalsView()
        case .reports: ReportsView()
        case .achievements: AchievementsView()
        case .community: CommunityView()
        case .settings: SettingsView()
        case .privacy: PrivacyView()
        }
    }
}
