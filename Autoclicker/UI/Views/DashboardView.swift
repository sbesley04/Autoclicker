import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissions: PermissionManager
    @Environment(\.hudStyle) private var style
    @Binding var section: SidebarSection

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !permissions.coreGranted {
                    permissionBanner
                }
                HStack(alignment: .top, spacing: 16) {
                    controlPanel
                    VStack(spacing: 16) {
                        statsPanel
                        configPanel
                    }
                }
                statusStrip
            }
            .padding(24)
            .frame(maxWidth: 860)
        }
    }

    // MARK: Permission warning

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(style.palette.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissions required")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(style.palette.textPrimary)
                Text("Accessibility access is missing — the engine cannot click and triggers cannot be detected.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.textSecondary)
            }
            Spacer()
            Button("Open Permissions") { section = .permissions }
                .buttonStyle(HUDButtonStyle(role: .destructive))
        }
        .hudPanel()
    }

    // MARK: Main control

    private var controlPanel: some View {
        VStack(spacing: 14) {
            ZStack {
                StatusRing(active: appState.isRunning, progress: limitProgress, size: 190)
                VStack(spacing: 4) {
                    if let countdown = appState.countdownRemaining {
                        Text("\(countdown)")
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .foregroundStyle(style.palette.warning)
                            .accessibilityLabel("Starting in \(countdown) seconds")
                    } else {
                        Text(appState.isRunning ? String(format: "%.1f", appState.currentCPS) : "—")
                            .font(.system(size: 38, weight: .bold, design: .monospaced))
                            .foregroundStyle(appState.isRunning ? style.accent : style.palette.textDim)
                        Text("CPS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(style.palette.textDim)
                    }
                }
            }

            Button {
                appState.toggleFromUI()
            } label: {
                Text(appState.isRunning ? "STOP" : "ENGAGE")
                    .frame(width: 150)
            }
            .buttonStyle(HUDButtonStyle(role: appState.isRunning ? .destructive : .normal, prominent: true))
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(appState.isRunning ? "Stop clicking" : "Start clicking")

            Toggle(isOn: armedBinding) {
                Text("TRIGGER ARMED")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(appState.isArmed ? style.accent : style.palette.textSecondary)
            }
            .toggleStyle(HUDToggleStyle())
            .disabled(!(appState.selectedProfile?.trigger.isAssigned ?? false) || !permissions.coreGranted)
            .help(appState.selectedProfile?.trigger.isAssigned == true
                  ? "When armed, the assigned trigger input starts and stops clicking globally."
                  : "Assign a trigger input first (Trigger section).")

            if appState.isRunning || appState.isArmed {
                Label("E-STOP: \(appState.emergencyStopDisplay)", systemImage: "octagon.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(style.palette.danger)
                    .padding(.top, 2)
            }
            if let reason = appState.lastStopReason, !appState.isRunning {
                Text(reason.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(reason == .emergencyStop ? style.palette.danger : style.palette.textDim)
            }
        }
        .frame(maxWidth: .infinity)
        .hudPanel(accented: appState.isRunning)
    }

    private var armedBinding: Binding<Bool> {
        Binding(get: { appState.isArmed }, set: { appState.isArmed = $0 })
    }

    private var limitProgress: Double? {
        guard appState.isRunning,
              let max = appState.selectedProfile.flatMap({ profile -> Int? in
                  switch profile.mode {
                  case .burst: return profile.speed.burstCount
                  default: return profile.safety.maxClicks
                  }
              }), max > 0 else { return nil }
        return Double(appState.sessionClicks) / Double(max)
    }

    // MARK: Stats

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Session Telemetry", systemImage: "waveform.path")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 14) {
                HUDStat(label: "Session Clicks", value: "\(appState.sessionClicks)")
                HUDStat(label: "Lifetime", value: "\(appState.lifetimeClicks)")
                HUDStat(label: "Duration", value: durationText)
                HUDStat(label: "Current CPS",
                        value: appState.isRunning ? String(format: "%.1f", appState.stats.currentCPS) : "—",
                        color: appState.isRunning ? style.accent : nil)
                HUDStat(label: "Avg CPS",
                        value: appState.stats.totalCount > 0
                            ? String(format: "%.1f", appState.stats.sessionAverageCPS) : "—")
                HUDStat(label: "Last Interval",
                        value: appState.stats.lastInterval.map { String(format: "%.0f ms", $0 * 1000) } ?? "—")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
    }

    private var durationText: String {
        let t = Int(appState.sessionDuration)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    // MARK: Config summary

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Active Configuration", systemImage: "slider.horizontal.3")
            if let profile = appState.selectedProfile {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 10) {
                    configItem("Profile", profile.name)
                    configItem("Trigger", profile.trigger.displayName)
                    configItem("Mode", profile.mode.displayName)
                    configItem("Click", profile.usesSequence ? "Sequence (\(profile.sequence.count))" : profile.clickType.displayName)
                    configItem("Speed", String(format: "%.1f cps est.", profile.estimatedCPS))
                    configItem("Targeting", profile.targeting.mode.displayName)
                }
            } else {
                Text("No profile selected")
                    .foregroundStyle(style.palette.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
    }

    private func configItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(style.palette.textDim)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(style.palette.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Status strip

    private var statusStrip: some View {
        HStack(spacing: 22) {
            StatusIndicator(
                state: permissions.accessibility.isGranted ? .good : .bad,
                label: "Accessibility")
            StatusIndicator(
                state: permissions.inputMonitoring.isGranted ? .good : .warning,
                label: "Input Monitoring")
            StatusIndicator(
                state: appState.monitor.isMonitoring ? .good : .neutral,
                label: "Event Tap")
            StatusIndicator(
                state: appState.isArmed ? .good : .neutral,
                label: "Trigger")
            Spacer()
            Button {
                appState.emergencyStop()
            } label: {
                Label("EMERGENCY STOP", systemImage: "octagon.fill")
            }
            .buttonStyle(HUDButtonStyle(role: .destructive, prominent: appState.isRunning))
            .accessibilityLabel("Emergency stop")
        }
        .hudPanel()
    }
}
