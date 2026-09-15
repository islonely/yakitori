import SwiftUI
import AppKit
import WritingTrackerCore

/// Plain-language explanation of what Yakitori does with your data.
struct PrivacyView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Privacy", subtitle: "Exactly what Yakitori sees, and what it never sees", symbol: "hand.raised.fill")

                shortVersion
                trackedSection
                neverSection
                appleScriptSection
                promptsSection
                dataSection
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Privacy")
    }

    private var shortVersion: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "The short version")
            Text("Yakitori is a writing tracker, not a writing tool. It counts how much you write and how long you write for, so it can show you progress over time. It never reads, stores, or sends your manuscript.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var trackedSection: some View {
        bulletCard(
            title: "What Yakitori tracks",
            symbol: "checkmark.circle",
            tint: .green,
            items: [
                "Which writing app is active, and when",
                "The document name and file path (for Word and Pages)",
                "How long you were focused, and how long you were actively writing",
                "The exact word count of your document, and how it changes",
                "The projects and goals you set up",
                "This Mac's hardware UUID, sent once to start a free trial and stored by the server only as a one-way hash (never the raw value)"
            ]
        )
    }

    private var neverSection: some View {
        bulletCard(
            title: "What Yakitori never touches",
            symbol: "xmark.circle",
            tint: .red,
            items: [
                "Your manuscript text (never read or stored)",
                "Individual keystrokes or what you type",
                "Your clipboard",
                "Screenshots or screen recordings",
                "Passwords or anything in secure fields",
                "Your camera, microphone, or location"
            ]
        )
    }

    private var appleScriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How it reads a word count (AppleScript)")
            Text("macOS includes a built-in automation system called AppleScript that lets apps securely ask each other for information. Yakitori uses it, and only it, to ask Microsoft Word or Pages two things: which document is open, and how many words it contains. Those apps answer with a name and a number.")
            Text("That means Yakitori never has to open, parse, or read your document. Word or Pages does the counting; we only receive the result.")
            Text("AppleScript is only used for apps that support it. For apps that don't (like Scrivener, Obsidian, or a browser), Yakitori tracks time and focus only, and shows \"Word count unavailable\" rather than guessing.")
            HStack {
                Button("Open Automation settings") {
                    state.openSystemSettings(for: .wordAutomation)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Prompts you might see", subtitle: "Yakitori asks for permissions only when a feature needs them, and keeps working if you say no. Activity tracking needs no permission at all.")
            prompt(
                "Automation (AppleScript)",
                "“Yakitori wants to control Microsoft Word.”",
                "Asks Word/Pages for the open document and its word count. Without it, sessions and time tracking still work; word counts are unavailable."
            )
            Divider()
            prompt(
                "Notifications",
                "“Yakitori would like to send you notifications.”",
                "Only requested if you turn notifications on. Used for goal and streak reminders. You can disable them any time."
            )
            Divider()
            prompt(
                "Login Items",
                "“Yakitori” appears under Login Items.",
                "Only added if you enable Launch at Login, so tracking can resume after a restart. Purely a setting; there is no prompt."
            )
            HStack(spacing: 10) {
                Button("Open Privacy & Security") {
                    state.openPrivacySettings()
                }
                Button("Open Permission Center") {
                    state.selectedSection = .settings
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Where your data lives")
            Text(AppPaths.isICloudBacked
                 ? "Your statistics are stored in iCloud Drive so they sync between your Macs."
                 : "Your statistics are stored in a local database on this Mac.")
                .foregroundStyle(.secondary)
            if AppPaths.isICloudBacked {
                Text("Use one Mac at a time: iCloud syncs whole files, so simultaneous edits on two Macs can conflict.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: AppPaths.databaseURL.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Reveal Database") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.databaseURL])
                }
                Button("Export / Back Up…") {
                    state.selectedSection = .settings
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func bulletCard(title: String, symbol: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func prompt(_ title: String, _ quote: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(quote).font(.callout).italic().foregroundStyle(.secondary)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }
    }
}
