import AppKit
import SwiftUI
import WritingTrackerCore

/// Account sign-in, license status, and installation management.
///
/// Signing in is entirely optional. The tracker keeps working offline and
/// without an account; this screen only affects licensing and future social
/// features.
struct AccountView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(
                    title: "Account",
                    subtitle: "Sign in to attach your lifetime license",
                    symbol: "person.crop.circle.fill"
                )

                switch state.accountState {
                case .signedIn(let user):
                    signedInSection(user)
                case .signedOut:
                    signedOutSection
                case .error(let message):
                    errorSection(message)
                }

                licensingSection
                localFirstSection
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Account")
    }

    // MARK: - Signed out

    private var signedOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Sign in",
                subtitle: "You'll approve this Mac in your browser. There is no password."
            )

            Text("Yakitori includes a 14-day free trial. Sign in to start it on this Mac — an account is required so a trial can't be restarted. Your writing data stays on this Mac either way.")
                .foregroundStyle(.secondary)
            SignInFlowView()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Signed in

    private func signedInSection(_ user: AccountUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Signed in")
            labeledRow("Email", user.email)
            labeledRow("Status", user.status.capitalized)
            labeledRow("Email verified", user.emailVerified ? "Yes" : "No")
            if let installationID = state.accountService.installationID {
                labeledRow("This Mac", installationID.uuidString)
            }
            HStack {
                Button("Refresh") { state.refreshLicense() }
                Button("Sign out") { state.signOutAccount() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Account problem")
            Text(message).foregroundStyle(.secondary)
            Button("Try again") { state.refreshLicense() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - License

    private var licensingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "License")

            switch state.licensingState {
            case .signedOut:
                Text("Sign in to check your license. A one-time purchase gives you a lifetime license.")
                    .foregroundStyle(.secondary)

            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your license…").foregroundStyle(.secondary)
                }

            case .active(let snapshot):
                licenseDetails(snapshot, badge: "Licensed", tint: .green)
                Text("A lifetime license is attached to this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .trial(let snapshot):
                licenseDetails(snapshot, badge: "Free trial", tint: .orange)
                Text("Your trial is running. Buy a lifetime license before it ends to keep tracking new sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .grace(let snapshot):
                licenseDetails(snapshot, badge: "Offline — grace period", tint: .orange)
                Text("The licensing server could not be reached. This is not a revocation; the app keeps working until the grace period ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .invalid(let reason):
                Text(invalidTitle(reason))
                    .foregroundStyle(.secondary)
                Text("Open Pricing on the website to buy a lifetime license, or sign in with the account that owns it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .unavailable(let reason):
                Text("Your license could not be verified right now (\(reason)). This is usually a network problem; try again shortly.")
                    .foregroundStyle(.secondary)

            case .clockAnomaly:
                Text("The system clock looks incorrect, so the offline license cannot be trusted. Connect to the network to revalidate.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func licenseDetails(_ snapshot: LicenseSnapshot, badge: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.15))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
            labeledRow("Product", snapshot.product)

            if snapshot.kind == .trial {
                if let days = snapshot.daysRemaining {
                    labeledRow("Days remaining", "\(days)")
                }
                if let endsAt = snapshot.entitlementExpiresAt {
                    labeledRow("Trial ends", Format.shortDayYear.string(from: endsAt))
                }
            } else {
                labeledRow("Type", snapshot.licenseType.capitalized)
                if let graceUntil = snapshot.offlineGraceUntil {
                    labeledRow("Offline grace until", Format.shortDayYear.string(from: graceUntil))
                }
            }
        }
    }

    private func invalidTitle(_ reason: String) -> String {
        switch reason {
        case "trial_expired":
            return "Your 14-day free trial has ended."
        case "trial_unavailable":
            return "This Mac has already used its free trial."
        case "revoked":
            return "This license was revoked (for example, after a refund)."
        case "disabled":
            return "This license is currently disabled."
        default:
            return "No active license (\(reason))."
        }
    }

    // MARK: - Local-first reminder

    private var localFirstSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Local-first, always")
            Text("Yakitori tracks your writing on this Mac whether or not you are signed in, and whether or not the network is available. An account is only needed to own a license and, later, to take part in community features.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Your license is not tied to this Mac. You can install Yakitori on as many Macs as you like, and reinstall it freely.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}
