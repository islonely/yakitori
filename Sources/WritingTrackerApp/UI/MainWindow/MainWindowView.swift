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
                        ForEach([SidebarSection.account, .settings, .privacy]) { section in
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

    private var detail: some View {
        VStack(spacing: 0) {
            if state.entitlementBannerVisible {
                entitlementBanner
            }
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var entitlementBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.gold)
            Text(state.entitlementMessage)
                .font(.callout)
            Spacer()
            Button("Open Account") { state.selectedSection = .account }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.ember.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.ember.opacity(0.22))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
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
        case .account: AccountView()
        case .settings: SettingsView()
        case .privacy: PrivacyView()
        }
    }
}
