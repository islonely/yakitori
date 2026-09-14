import SwiftUI
import WritingTrackerCore

struct PermissionCenterView: View {
    @EnvironmentObject private var state: AppState

    private let explanations: [PermissionKind: String] = [
        .wordAutomation: "Lets Yakitori ask Microsoft Word or Pages for the active document and its exact word count. Document text is never read or stored.",
        .fileAccess: "Only used for files or folders you explicitly select. Full Disk Access is never requested.",
        .notifications: "Used to deliver goal, streak, and milestone notifications. Optional.",
        .launchAtLogin: "Allows background tracking to begin automatically after you log in."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Permission Center", subtitle: "Activity tracking needs no permission; capabilities degrade gracefully when optional permissions are unavailable")
            ForEach(PermissionKind.allCases) { kind in
                permissionRow(kind)
                if kind != PermissionKind.allCases.last { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func permissionRow(_ kind: PermissionKind) -> some View {
        let status = state.container.permissionProvider.status(for: kind)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.displayName).font(.body.weight(.medium))
                Spacer()
                PermissionBadge(state: status.state)
            }
            Text(explanations[kind] ?? "")
                .font(.caption).foregroundStyle(.secondary)
            if status.state == .denied || status.state == .notDetermined {
                HStack(spacing: 8) {
                    if status.state == .notDetermined, kind != .fileAccess {
                        Button("Grant") { state.requestPermission(kind) }
                    }
                    Button("Open System Settings") { state.openSystemSettings(for: kind) }
                }
                .buttonStyle(.link)
            }
        }
    }
}
