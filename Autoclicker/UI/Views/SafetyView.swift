import SwiftUI

struct SafetyView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.hudStyle) private var style
    @State private var recordingShortcut = false

    var body: some View {
        HUDScreen(title: "Safety",
                  subtitle: "Hard limits and the emergency stop. The emergency stop always outranks every trigger.") {
            emergencyPanel
            if let profile = appState.selectedProfileBinding {
                limitsPanel(profile)
                behaviorPanel(profile)
            } else {
                NoProfilePlaceholder()
            }
        }
        .onDisappear {
            if recordingShortcut {
                recordingShortcut = false
                appState.endInputDetection(assign: false)
            }
        }
    }

    // MARK: Emergency stop

    private var emergencyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Emergency Stop", systemImage: "octagon")
            HStack(spacing: 14) {
                Text(settingsStore.settings.emergencyStop.displayName)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(style.palette.danger)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(AngularPanel(cut: 8).fill(style.palette.danger.opacity(0.08))
                        .overlay(AngularPanel(cut: 8).stroke(style.palette.danger.opacity(0.7), lineWidth: 1)))
                    .shadow(color: style.palette.danger.opacity(0.4 * style.glow), radius: style.glowRadius(8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Global shortcut — works everywhere, even while another app is frontmost.")
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.textSecondary)
                    Text("Stops the engine instantly (interrupting any wait) and disarms the trigger.")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
                Spacer()
            }

            if recordingShortcut {
                HStack(spacing: 8) {
                    PulsingDot(active: true, color: style.palette.warning)
                    Text("Press the new shortcut (a key with at least one modifier)…")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(style.palette.warning)
                    Button("Cancel") {
                        recordingShortcut = false
                        appState.endInputDetection(assign: false)
                    }
                    .buttonStyle(HUDButtonStyle())
                }
                .onChange(of: appState.lastDetectedCandidate) { candidate in
                    guard recordingShortcut,
                          case .keyDown(let keyCode, let modifiers)? = candidate?.kind,
                          !modifiers.isEmpty else { return }
                    settingsStore.settings.emergencyStop = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                    recordingShortcut = false
                    appState.endInputDetection(assign: false)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Change Shortcut") {
                        recordingShortcut = true
                        appState.beginInputDetection()
                    }
                    .buttonStyle(HUDButtonStyle())
                    .disabled(!appState.monitor.isMonitoring)
                    Button("Reset to ⌘⇧⎋") {
                        settingsStore.settings.emergencyStop = .defaultEmergencyStop
                    }
                    .buttonStyle(HUDButtonStyle())
                    Spacer()
                    Button {
                        appState.emergencyStop()
                    } label: {
                        Label("TEST EMERGENCY STOP", systemImage: "octagon.fill")
                    }
                    .buttonStyle(HUDButtonStyle(role: .destructive))
                }
            }
        }
        .hudPanel(accented: true)
    }

    // MARK: Limits

    private func limitsPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Session Limits", systemImage: "ruler")

            HUDRow(label: "Maximum Click Count",
                   detail: "Stop automatically after this many clicks") {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { profile.wrappedValue.safety.maxClicks != nil },
                        set: { profile.wrappedValue.safety.maxClicks = $0 ? 1000 : nil })) { EmptyView() }
                        .toggleStyle(HUDToggleStyle())
                        .accessibilityLabel("Enable maximum click count")
                    if profile.wrappedValue.safety.maxClicks != nil {
                        HUDNumberField(
                            value: Binding(
                                get: { Double(profile.wrappedValue.safety.maxClicks ?? 1000) },
                                set: { profile.wrappedValue.safety.maxClicks = Int($0) }),
                            range: 1...1_000_000, unit: "clicks")
                    }
                }
            }

            HUDRow(label: "Maximum Runtime",
                   detail: "Stop automatically after this much time") {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { profile.wrappedValue.safety.maxRuntimeSeconds != nil },
                        set: { profile.wrappedValue.safety.maxRuntimeSeconds = $0 ? 60 : nil })) { EmptyView() }
                        .toggleStyle(HUDToggleStyle())
                        .accessibilityLabel("Enable maximum runtime")
                    if profile.wrappedValue.safety.maxRuntimeSeconds != nil {
                        HUDNumberField(
                            value: Binding(
                                get: { profile.wrappedValue.safety.maxRuntimeSeconds ?? 60 },
                                set: { profile.wrappedValue.safety.maxRuntimeSeconds = $0 }),
                            range: 1...86_400, unit: "s")
                    }
                }
            }

            HUDSliderRow(label: "Startup Countdown",
                         value: profile.safety.countdownSeconds,
                         range: 0...30, unit: "s",
                         detail: "Delay before clicking begins, with an on-screen count")
        }
        .hudPanel()
    }

    // MARK: Behavior

    private func behaviorPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Automatic Stops", systemImage: "hand.raised")

            Toggle(isOn: profile.safety.stopOnAppSwitch) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stop when the active application changes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.palette.textPrimary)
                    Text("Prevents clicking into a window you didn't intend")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .toggleStyle(HUDToggleStyle())

            Toggle(isOn: Binding(
                get: { settingsStore.settings.rememberArmedState },
                set: { settingsStore.settings.rememberArmedState = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remember armed state between launches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.palette.textPrimary)
                    Text("Re-arms the trigger on launch if it was armed when you quit. Clicking still only starts when you press your trigger.")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .toggleStyle(HUDToggleStyle())

            Toggle(isOn: profile.safety.confirmHighRates) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Confirm before extremely high click rates")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.palette.textPrimary)
                    Text("Ask before starting sessions above \(Int(SpeedConfig.highRateThresholdCPS)) clicks per second")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .toggleStyle(HUDToggleStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Always-on protections")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(style.palette.textSecondary)
                ForEach([
                    "Clicking stops when the app quits",
                    "Clicking stops if Accessibility permission is revoked",
                    "Clicking stops when the system sleeps",
                    "Sessions stop on display layout changes when using saved coordinates",
                    "Held mouse buttons are always released when a session ends",
                ], id: \.self) { line in
                    Label(line, systemImage: "checkmark.shield")
                        .font(.system(size: 10.5))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .padding(.top, 4)
        }
        .hudPanel()
    }
}
