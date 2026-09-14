import SwiftUI
import WritingTrackerCore

/// Shown briefly at launch while the stored session is being checked, so the
/// signed-out gate never flashes for a user who is actually signed in.
struct SessionLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            YakitoriMark(size: 56)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brandBackground()
    }
}

/// Shown instead of the main interface when the user is not signed in.
///
/// Yakitori's 14-day trial is account-bound so it cannot be restarted, which
/// means an account is the entry point rather than a setting buried in a tab.
struct WelcomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 26) {
                VStack(spacing: 16) {
                    YakitoriMark(size: 76)
                    VStack(spacing: 8) {
                        Text("Welcome to Yakitori")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("A local-first writing tracker for your Mac.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                trialCard

                VStack(spacing: 8) {
                    SignInFlowView()
                    Text("Already own Yakitori? Sign in with the account that holds your license.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                privacyNote
            }
            .frame(maxWidth: 560)
            .padding(40)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brandBackground()
    }

    private var trialCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("14-day free trial", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.gold)

            Text("Every feature is unlocked for 14 days. No card required. An account is needed so a trial can be used only once.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Exact word counts in Word and Pages")
                bullet("Streaks, goals, projects, and full analytics")
                bullet("Works offline once you're signed in")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var privacyNote: some View {
        Label(
            "Your manuscript never leaves this Mac. Yakitori only stores aggregate numbers.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.ember)
                .font(.caption)
                .padding(.top, 2)
            Text(text).font(.callout)
        }
    }
}
