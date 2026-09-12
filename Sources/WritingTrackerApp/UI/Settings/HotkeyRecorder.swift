import SwiftUI
import AppKit
import Carbon
import WritingTrackerCore

/// Records a global keyboard shortcut for starting/stopping a session.
struct HotkeyRecorder: View {
    @EnvironmentObject private var state: AppState
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Start/stop session hotkey")
            Spacer()
            Text(state.settings.globalHotkey?.display ?? (isRecording ? "Press keys…" : "None"))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? Theme.accent : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button(isRecording ? "Cancel" : "Record") {
                isRecording ? cancelRecording() : beginRecording()
            }
            Button("Clear") {
                state.updateSettings { $0.globalHotkey = nil }
            }
            .disabled(state.settings.globalHotkey == nil)
        }
        .onDisappear { cancelRecording() }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels recording.
            if event.keyCode == 53 {
                cancelRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Require at least one modifier so ordinary typing is never captured.
            guard !flags.isEmpty else { return nil }
            let config = HotkeyConfiguration(
                keyCode: event.keyCode,
                carbonModifiers: Self.carbonModifiers(flags),
                display: Self.displayString(flags: flags, characters: event.charactersIgnoringModifiers ?? "?"),
                enabled: true
            )
            state.updateSettings { $0.globalHotkey = config }
            cancelRecording()
            return nil
        }
    }

    private func cancelRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static func displayString(flags: NSEvent.ModifierFlags, characters: String) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += characters.uppercased()
        return text
    }
}
