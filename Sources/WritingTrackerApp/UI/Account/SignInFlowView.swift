import SwiftUI
import WritingTrackerCore

/// The device-authorization sign-in flow, shared by the signed-out welcome gate
/// and the Account screen.
struct SignInFlowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.isDeviceSignInPresented, let authorization = state.deviceAuthorization {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter this code in your browser to approve this Mac:")
                    .foregroundStyle(.secondary)
                Text(authorization.userCode)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button("Open Browser") { state.openDeviceVerificationPage() }
                    Button("Cancel") { state.cancelDeviceSignIn() }
                    ProgressView()
                        .controlSize(.small)
                }
                .buttonStyle(.bordered)

                if let error = state.deviceSignInError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let error = state.deviceSignInError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Button {
                    state.beginDeviceSignIn()
                } label: {
                    Label(
                        "Sign in or start free trial",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
