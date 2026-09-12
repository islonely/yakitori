import SwiftUI
import AppKit
import WritingTrackerCore

struct CommunityView: View {
    @EnvironmentObject private var state: AppState
    @State private var kind: LeaderboardKind = .wordsThisWeek
    @State private var refreshToken = 0

    private var social: SocialService { state.container.social }
    private var currentUserID: String { SocialService.currentUserID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Community", subtitle: "Leaderboards and writers you follow", symbol: "person.3.fill")

                if !state.settings.publishStatsEnabled {
                    publishPrompt
                } else {
                    publishStatus
                }

                leaderboardSection
                followingSection
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Community")
        .id(refreshToken)
        .onChange(of: state.dataVersion) { _ in refreshToken &+= 1 }
    }

    private var publishPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Share your progress", subtitle: "Off by default")
            Text("Publish an aggregate snapshot of your stats to appear on leaderboards. Only numbers are shared — never documents, project names, or text. You can turn this off at any time.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                state.updateSettings { $0.publishStatsEnabled = true }
                state.publishCommunityStats()
            } label: {
                Label("Enable sharing", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var publishStatus: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sharing is on").font(.headline)
                Text("Publishing as \(state.settings.communityDisplayName?.isEmpty == false ? state.settings.communityDisplayName! : "You")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Publish now") { state.publishCommunityStats(); refreshToken &+= 1 }
                .buttonStyle(.bordered)
            Button("Stop sharing") {
                state.updateSettings { $0.publishStatsEnabled = false }
                state.unpublishCommunityStats()
                refreshToken &+= 1
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Leaderboards", subtitle: "Placements update as you finish sessions")
            Picker("Board", selection: $kind) {
                ForEach(LeaderboardKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 220)

            let entries = social.leaderboard(kind: kind)
            if entries.isEmpty {
                Text("No one is on this board yet. Enable sharing to add yourself.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                        if entry.id != entries.last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(.headline, design: .rounded))
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(entry.rank <= 3 ? Theme.accent : .secondary)
            avatar(entry.profile)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.profile.displayName).font(.subheadline.weight(.medium))
                    if entry.profile.isCurrentUser {
                        Text("YOU").font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                    if entry.profile.isSample {
                        Text("SAMPLE").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(kind.formatted(entry.value)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !entry.profile.isCurrentUser {
                followButton(entry.profile)
            }
        }
        .padding(.vertical, 8)
    }

    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Writers you follow", subtitle: "Compare your stats against theirs")
            let followed = social.followedProfiles()
            if followed.isEmpty {
                Text("Follow a writer from a leaderboard to compare stats.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(followed) { profile in
                    comparisonCard(profile)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func comparisonCard(_ profile: CommunityProfile) -> some View {
        let rows = social.comparison(with: profile)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                avatar(profile)
                Text(profile.displayName).font(.headline)
                Spacer()
                followButton(profile)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.label).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.formattedYou).frame(width: 90, alignment: .trailing)
                    Text(row.formattedThem).frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    Text(row.formattedDelta)
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(row.delta >= 0 ? .green : .orange)
                }
                .font(.callout)
                if row.id != rows.last?.id { Divider() }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func followButton(_ profile: CommunityProfile) -> some View {
        let following = social.isFollowing(profile.id)
        return Button {
            try? following ? social.unfollow(profile.id) : social.follow(profile.id)
            refreshToken &+= 1
        } label: {
            Label(following ? "Following" : "Follow", systemImage: following ? "checkmark" : "plus")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(following ? .secondary : Theme.accent)
    }

    private func avatar(_ profile: CommunityProfile) -> some View {
        Text(profile.initials)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.brandGradient)
            .clipShape(Circle())
    }
}
