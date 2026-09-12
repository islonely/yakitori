import SwiftUI
import WritingTrackerCore

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
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
                    ForEach([SidebarSection.goals, .reports, .achievements, .settings]) { section in
                        sidebarRow(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $state.isOnboardingPresented) {
            OnboardingView()
                .environmentObject(state)
        }
        .preferredColorScheme(state.settings.appearance.colorScheme)
        .alert("Writing Tracker", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
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
        case .settings: SettingsView()
        }
    }
}
