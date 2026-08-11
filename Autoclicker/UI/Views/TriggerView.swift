import SwiftUI

struct TriggerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style

    var body: some View {
        HUDScreen(title: "Trigger",
                  subtitle: "Assign the mouse button or keyboard shortcut that activates this profile. Mouse Button 3 and 4 are fully supported.") {
            if let profile = appState.selectedProfileBinding {
                currentTriggerPanel(profile)
                detectionPanel
                behaviorPanel(profile)
                diagnosticsPanel
            } else {
                NoProfilePlaceholder()
            }
        }
        .onDisappear {
            appState.diagnosticsEnabled = false
            if appState.isDetectingInput { appState.endInputDetection(assign: false) }
        }
    }

    // MARK: Current assignment

    private func currentTriggerPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Assigned Trigger", systemImage: "scope")
            HStack(spacing: 14) {
                Text(profile.wrappedValue.trigger.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(profile.wrappedValue.trigger.isAssigned ? style.accent : style.palette.textDim)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(AngularPanel(cut: 8).fill(Color.black.opacity(0.35))
                        .overlay(AngularPanel(cut: 8).stroke(style.accent.opacity(0.4), lineWidth: 1)))
                Spacer()
                if profile.wrappedValue.trigger.isAssigned {
                    Button("Clear") {
                        appState.isArmed = false
                        profile.wrappedValue.trigger = .none
                    }
                    .buttonStyle(HUDButtonStyle())
                }
            }
            Text("Quick assign:")
                .font(.system(size: 10.5))
                .foregroundStyle(style.palette.textDim)
            HStack(spacing: 6) {
                quickAssign(profile, "Middle (2)", .mouseButton(number: 2))
                quickAssign(profile, "Button 3", .mouseButton(number: 3))
                quickAssign(profile, "Button 4", .mouseButton(number: 4))
                quickAssign(profile, "F6", .keyboard(keyCode: 97, modifiers: []))
                quickAssign(profile, "⌘⌥C", .keyboard(keyCode: 8, modifiers: [.command, .option]))
            }
        }
        .hudPanel()
    }

    private func quickAssign(_ profile: Binding<Profile>, _ label: String, _ trigger: TriggerInput) -> some View {
        Button(label) { profile.wrappedValue.trigger = trigger }
            .buttonStyle(HUDButtonStyle())
    }

    // MARK: Detection mode

    private var detectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Input Detection Mode", systemImage: "dot.radiowaves.left.and.right")
            Text("Mouse button numbering differs between manufacturers and drivers. Press Detect, then press any mouse button or key — the raw event type and button number are shown so you can verify what macOS actually reports.")
                .font(.system(size: 10.5))
                .foregroundStyle(style.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.isDetectingInput {
                VStack(alignment: .leading, spacing: 10) {
                    let captured = appState.lastDetectedCandidate != nil
                    HStack(spacing: 8) {
                        PulsingDot(active: !captured,
                                   color: captured ? style.palette.good : style.palette.warning)
                        Text(captured
                             ? "CAPTURED — assign it, or detect again"
                             : "LISTENING — press a mouse button or key…")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(captured ? style.palette.good : style.palette.warning)
                    }
                    if let candidate = appState.lastDetectedCandidate {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.eventTypeName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundStyle(style.palette.textDim)
                            Text(candidate.detailText)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(style.accent)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AngularPanel(cut: 8).fill(style.accent.opacity(0.07))
                            .overlay(AngularPanel(cut: 8).stroke(style.accent.opacity(0.5), lineWidth: 1)))
                    }
                    HStack {
                        Button("Assign as Trigger") { appState.endInputDetection(assign: true) }
                            .buttonStyle(HUDButtonStyle(prominent: true))
                            .disabled(appState.lastDetectedCandidate?.asTrigger == nil)
                        if appState.lastDetectedCandidate != nil {
                            Button("Detect Again") { appState.retryInputDetection() }
                                .buttonStyle(HUDButtonStyle())
                        }
                        Button("Cancel") { appState.endInputDetection(assign: false) }
                            .buttonStyle(HUDButtonStyle())
                    }
                }
            } else {
                Button {
                    appState.beginInputDetection()
                } label: {
                    Label("Detect Input", systemImage: "wave.3.right")
                }
                .buttonStyle(HUDButtonStyle(prominent: true))
                .disabled(!appState.monitor.isMonitoring)
                if !appState.monitor.isMonitoring {
                    Text("Global monitoring is unavailable — grant Accessibility permission first.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(style.palette.danger)
                }
            }
        }
        .hudPanel(accented: appState.isDetectingInput)
    }

    // MARK: Input behavior

    private func behaviorPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Original Event Handling", systemImage: "arrow.triangle.branch")
            HUDSegmentedPicker(
                options: InputBehavior.allCases,
                selection: profile.inputBehavior,
                label: { $0.displayName })
            Text(profile.wrappedValue.inputBehavior.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(style.palette.textSecondary)
            if profile.wrappedValue.inputBehavior.wantsSuppression && !appState.monitor.canSuppress {
                Label("Suppression is unavailable right now (the event tap is listen-only). The input will pass through until Accessibility permission allows an active tap.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.warning)
            }
            if case .mouseButton(let n) = profile.wrappedValue.trigger, n == 0 {
                Label("Suppressing the left mouse button is dangerous — you could lose the ability to click. Pass-through is strongly recommended for the left button.",
                      systemImage: "exclamationmark.octagon.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.danger)
            }
        }
        .hudPanel()
    }

    // MARK: Diagnostics

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HUDSectionHeader(title: "Input Diagnostics", systemImage: "stethoscope")
                Toggle(isOn: $appState.diagnosticsEnabled) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(style.palette.textSecondary)
                }
                .toggleStyle(HUDToggleStyle())
            }
            Text("Recent input events seen by the global monitor. Synthetic events generated by the click engine are tagged SYN and never re-trigger the app.")
                .font(.system(size: 10))
                .foregroundStyle(style.palette.textDim)
            if appState.diagnosticsEnabled {
                if appState.recentInputs.isEmpty {
                    Text("Waiting for input events…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(style.palette.textDim)
                } else {
                    VStack(spacing: 2) {
                        ForEach(appState.recentInputs.prefix(14)) { input in
                            HStack(spacing: 8) {
                                Text(Self.timeFormatter.string(from: input.timestamp))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(style.palette.textDim)
                                Text(input.eventTypeName)
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundStyle(style.palette.textSecondary)
                                Text(input.detailText)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(style.accent)
                                Spacer()
                                if input.isSynthetic {
                                    Text("SYN")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(style.palette.background)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(style.secondary))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .hudPanel()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
