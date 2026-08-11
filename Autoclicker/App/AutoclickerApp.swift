import SwiftUI

// The @main attribute is compiled out for the headless test-runner build
// (see Scripts/run-tests.sh), which supplies its own entry point.
#if !TEST_RUNNER
@main
#endif
struct AutoclickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var appState: AppState

    static let mainWindowID = "autoclicker-main"

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        AppDelegate.sharedState = state
    }

    var body: some Scene {
        WindowGroup("Autoclicker", id: Self.mainWindowID) {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(appState.profileStore)
                .environmentObject(appState.settingsStore)
                .environmentObject(appState.permissions)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Control") {
                Button(appState.isRunning ? "Stop" : "Start") {
                    appState.toggleFromUI()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Emergency Stop") {
                    appState.emergencyStop()
                }
                .keyboardShortcut(.escape, modifiers: [.command, .shift])

                Divider()

                Button(appState.isArmed ? "Disarm Trigger" : "Arm Trigger") {
                    appState.isArmed.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(isInserted: menuBarVisible) {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isRunning ? "cursorarrow.rays" : "cursorarrow.click.badge.clock")
                .accessibilityLabel(appState.isRunning ? "Autoclicker running" : "Autoclicker idle")
        }
    }

    private var menuBarVisible: Binding<Bool> {
        Binding(
            get: { appState.settingsStore.settings.showMenuBarItem },
            // MenuBarExtra writes this binding back on every graph update.
            // Guard against no-op writes: @Published fires didSet even when
            // the value is unchanged, which here would loop
            // objectWillChange → body → write → objectWillChange forever.
            set: { newValue in
                if appState.settingsStore.settings.showMenuBarItem != newValue {
                    appState.settingsStore.settings.showMenuBarItem = newValue
                }
            })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        // Guarantees clicking stops and monitors/timers are torn down even
        // when the app is quit while a session is active.
        Self.sharedState?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(Self.sharedState?.settingsStore.settings.keepRunningWhenWindowCloses ?? true)
    }
}
