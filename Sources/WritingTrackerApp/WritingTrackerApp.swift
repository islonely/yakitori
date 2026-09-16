import SwiftUI
import AppKit
import UserNotifications
import WritingTrackerCore

@main
struct YakitoriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(state)
                .environmentObject(state.tracking)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
                .environmentObject(state.tracking)
        }
        .menuBarExtraStyle(.window)

        // WindowGroup (not Window) so the app behaves like a normal app: it has
        // a Dock icon, appears in Spotlight/Launchpad when installed, and
        // reopening from the Dock restores the window.
        WindowGroup("Yakitori", id: "dashboard") {
            Group {
                if !state.accountLoaded {
                    SessionLoadingView()
                } else if state.isSignedIn {
                    MainWindowView()
                } else {
                    WelcomeView()
                }
            }
            .environmentObject(state)
            .environmentObject(state.tracking)
            .tint(Theme.accent)
            .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Yakitori") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            // Single-window app: no File > New Window.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A normal app: Dock icon, Spotlight/Launchpad discovery, menu bar extra
        // still available.
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self

        // Headless diagnostic mode: `Yakitori --diagnostics [--probe-word]`
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            let container = AppState.shared.container
            let diagnostics = DiagnosticsService(
                database: container.database,
                databaseURL: container.database.filePath.map {
                    URL(fileURLWithPath: $0)
                },
                permissionProvider: container.permissionProvider
            )
            let probe = ProcessInfo.processInfo.arguments.contains("--probe-word")
            print(diagnostics.jsonString(probeWord: probe))
            exit(0)
        }

        AppState.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the dashboard must not stop background tracking.
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Clicking the Dock icon brings the dashboard back.
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // Allow banners while the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
