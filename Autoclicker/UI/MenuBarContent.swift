import SwiftUI
import AppKit

/// Contents of the optional menu bar item (menu style).
struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(statusLine)
            if appState.isRunning {
                Text(String(format: "%.1f cps — %d clicks", appState.currentCPS, appState.sessionClicks))
            } else if appState.lifetimeClicks > 0 {
                Text("\(appState.lifetimeClicks) clicks this run")
            }

            Divider()

            Button(appState.isRunning ? "Stop" : "Start “\(appState.selectedProfile?.name ?? "—")”") {
                appState.toggleFromUI()
            }
            .disabled(appState.selectedProfile == nil)

            Button("Emergency Stop") {
                appState.emergencyStop()
            }

            Button(appState.isArmed ? "Disarm Trigger" : "Arm Trigger") {
                appState.isArmed.toggle()
            }
            .disabled(!(appState.selectedProfile?.trigger.isAssigned ?? false))

            Divider()

            Menu("Profiles") {
                ForEach(appState.profileStore.profiles) { profile in
                    Button {
                        appState.selectProfile(profile.id)
                    } label: {
                        if profile.id == appState.profileStore.selectedProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()

            Button("Open Autoclicker") {
                NSApp.activate(ignoringOtherApps: true)
                // Reuse an existing window if one is still open, otherwise
                // recreate it via the scene's openWindow action (the window
                // is destroyed when closed with keep-running enabled).
                if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: AutoclickerApp.mainWindowID)
                }
            }

            Button("Quit Autoclicker") {
                NSApp.terminate(nil)
            }
        }
    }

    private var statusLine: String {
        if appState.isRunning { return "● Running — \(appState.selectedProfile?.name ?? "")" }
        if appState.isArmed { return "◆ Armed — waiting for trigger" }
        return "○ Standby"
    }
}
