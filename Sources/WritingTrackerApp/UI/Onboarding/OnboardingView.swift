import SwiftUI
import WritingTrackerCore

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var projectTitle = ""
    @State private var projectTarget = ""
    @State private var projectDeadline = Date()
    @State private var hasDeadline = false

    private let stepCount = 7

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 620, height: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: applicationsStep
        case 2: modeStep
        case 3: accessibilityStep
        case 4: wordStep
        case 5: projectStep
        default: doneStep
        }
    }

    private var welcomeStep: some View {
        stepLayout(
            symbol: "square.and.pencil",
            title: "Track your writing without changing where you write",
            body: "Writing Tracker runs quietly while you write in apps like Microsoft Word. It records activity, timing, and word-count changes without storing your manuscript.\n\n• No manuscript text stored\n• No keystrokes stored (word estimates for some apps use a session-only buffer that is discarded when the session ends)\n• No screenshots\n• Data stays on your Mac"
        )
    }

    private var applicationsStep: some View {
        let apps = (try? state.container.applicationRepository.all()) ?? []
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose writing applications").font(.title2.weight(.semibold))
            Text("Only selected applications count toward automatic tracking. You can change this later.")
                .foregroundStyle(.secondary)
            if apps.isEmpty {
                Text("No known writing applications detected on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(apps) { app in
                            Toggle(isOn: applicationBinding(app)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.displayName)
                                    Text(app.adapterType.displayName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .padding(28)
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a tracking mode").font(.title2.weight(.semibold))
            ForEach(TrackingMode.allCases) { mode in
                Button {
                    state.updateSettings { $0.trackingMode = mode }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: state.settings.trackingMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName).font(.body.weight(.medium))
                            Text(modeExplanation(mode)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.primary.opacity(state.settings.trackingMode == mode ? 0.06 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
    }

    private var accessibilityStep: some View {
        stepLayout(
            symbol: "hand.raised",
            title: "Accessibility permission",
            body: "Accessibility lets Writing Tracker detect that you are active in another app. The app records activity timestamps only — it never saves what you type.",
            primary: ("Grant Accessibility Permission", { state.requestPermission(.accessibility) }),
            secondary: ("Skip for Now", { advance() })
        )
    }

    private var wordStep: some View {
        let wordEnabled = state.settings.selectedApplicationIDs.contains { id in
            (try? state.container.applicationRepository.find(id: id))?.adapterType == .word
        }
        return stepLayout(
            symbol: "doc.text.magnifyingglass",
            title: "Microsoft Word integration",
            body: wordEnabled
                ? "Word integration lets Writing Tracker ask Word for the active document and word count. Your document text is never stored by Writing Tracker."
                : "Word integration is optional. If Word is not one of your writing applications, you can skip this step.",
            primary: wordEnabled ? ("Grant Word Automation", { state.requestPermission(.wordAutomation) }) : nil,
            secondary: ("Continue", { advance() })
        )
    }

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create your first project").font(.title2.weight(.semibold))
            Text("A project groups your writing — a novel, article, thesis, or blog.").foregroundStyle(.secondary)
            Form {
                TextField("Project name", text: $projectTitle)
                TextField("Target word count (optional)", text: $projectTarget)
                Toggle("Set a deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline", selection: $projectDeadline, displayedComponents: .date)
                }
            }
        }
        .padding(28)
    }

    private var doneStep: some View {
        stepLayout(
            symbol: "checkmark.circle",
            title: "Writing Tracker is ready",
            body: "You can write normally in your chosen applications. Close the dashboard whenever you like — background tracking continues."
        )
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            Text("Step \(step + 1) of \(stepCount)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(step == stepCount - 1 ? "Get Started" : "Continue") {
                if step == 5 { createProject() }
                else if step == stepCount - 1 { finish() }
                else { advance() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    @ViewBuilder
    private func stepLayout(
        symbol: String,
        title: String,
        body: String,
        primary: (String, () -> Void)? = nil,
        secondary: (String, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 46))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            if let primary {
                Button(primary.0) { primary.1() }
                    .buttonStyle(.borderedProminent)
            }
            if let secondary {
                Button(secondary.0) { secondary.1() }
                    .buttonStyle(.link)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applicationBinding(_ app: WritingApplication) -> Binding<Bool> {
        Binding(
            get: { state.settings.selectedApplicationIDs.contains(app.id) },
            set: { isOn in
                state.updateSettings { settings in
                    if isOn {
                        if !settings.selectedApplicationIDs.contains(app.id) {
                            settings.selectedApplicationIDs.append(app.id)
                        }
                    } else {
                        settings.selectedApplicationIDs.removeAll { $0 == app.id }
                    }
                }
            }
        )
    }

    private func modeExplanation(_ mode: TrackingMode) -> String {        switch mode {
        case .manual: return "You explicitly start and stop each writing session."
        case .automatic: return "Any recognized writing application is tracked automatically."
        case .automaticFiltered: return "Only your selected applications are tracked automatically."
        }
    }

    private func advance() {
        step = min(step + 1, stepCount - 1)
    }

    private func createProject() {
        let title = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { advance(); return }
        let target = Int(projectTarget.trimmingCharacters(in: .whitespaces))
        do {
            let project = try state.container.projects.createProject(
                title: title,
                targetWordCount: target,
                deadline: hasDeadline ? projectDeadline : nil
            )
            state.updateSettings { $0.currentProjectID = project.id }
        } catch {
            state.presentError(error)
        }
        step += 1
    }

    private func finish() {
        state.completeOnboarding()
        dismiss()
    }
}
