import SwiftUI

struct ClickEngineView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style

    var body: some View {
        HUDScreen(title: "Click Engine",
                  subtitle: "Activation mode, click type and speed for the active profile.") {
            if let profile = appState.selectedProfileBinding {
                modePanel(profile)
                clickTypePanel(profile)
                speedPanel(profile)
                validationPanel(profile.wrappedValue)
            } else {
                NoProfilePlaceholder()
            }
        }
    }

    // MARK: Activation mode

    private func modePanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Activation Mode", systemImage: "bolt.horizontal.circle")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ActivationMode.allCases) { mode in
                    modeCard(profile, mode)
                }
            }
            if profile.wrappedValue.mode == .humanizedRapid {
                Label("Timing for Humanized Rapid mode is configured in the Humanization section.",
                      systemImage: "waveform.path.ecg")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.textSecondary)
            }
            if profile.wrappedValue.mode == .repeatSequence {
                Label("This mode runs the action sequence — build it in the Sequence section.",
                      systemImage: "list.number")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.textSecondary)
            }
        }
        .hudPanel()
    }

    private func modeCard(_ profile: Binding<Profile>, _ mode: ActivationMode) -> some View {
        let selected = profile.wrappedValue.mode == mode
        return Button {
            profile.wrappedValue.mode = mode
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? style.accent : style.palette.textSecondary)
                    Text(mode.displayName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? style.palette.textPrimary : style.palette.textSecondary)
                }
                Text(mode.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(style.palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                AngularPanel(cut: 8)
                    .fill(selected ? style.accent.opacity(0.1) : Color.white.opacity(0.03))
                    .overlay(AngularPanel(cut: 8).stroke(
                        selected ? style.accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Click type

    private func clickTypePanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Click Type", systemImage: "cursorarrow.click")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                ForEach(ClickType.allCases) { type in
                    let selected = profile.wrappedValue.clickType == type
                    Button {
                        profile.wrappedValue.clickType = type
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.systemImage)
                                .font(.system(size: 14))
                            Text(type.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(selected ? style.accent : style.palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            AngularPanel(cut: 6)
                                .fill(selected ? style.accent.opacity(0.1) : Color.white.opacity(0.03))
                                .overlay(AngularPanel(cut: 6).stroke(
                                    selected ? style.accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.displayName)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            if profile.wrappedValue.clickType == .clickAndHold {
                HUDSliderRow(label: "Hold Duration",
                             value: profile.holdDurationMS,
                             range: 10...10_000, unit: "ms",
                             detail: "How long the button stays pressed each cycle")
            }
            if profile.wrappedValue.usesSequence {
                Label("The action sequence overrides the click type for this mode.",
                      systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(style.palette.textDim)
            }
        }
        .hudPanel()
    }

    // MARK: Speed

    private func speedPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Speed", systemImage: "speedometer")

            if profile.wrappedValue.mode == .burst {
                HUDSliderRow(label: "Burst Click Count",
                             value: Binding(
                                get: { Double(profile.wrappedValue.speed.burstCount) },
                                set: { profile.wrappedValue.speed.burstCount = Int($0) }),
                             range: 1...500,
                             detail: "Exact number of clicks per activation")
                HUDSliderRow(label: "Burst Interval",
                             value: profile.speed.burstIntervalMS,
                             range: 1...2000, unit: "ms",
                             detail: "Delay between clicks inside a burst")
            } else if profile.wrappedValue.mode == .humanizedRapid {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(style.accent)
                    Text(String(format: "Humanized Rapid targets %.1f cps with natural variation — tune it in the Humanization section.",
                                profile.wrappedValue.humanizedRapid.targetCPS))
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.textSecondary)
                }
            } else {
                HUDRow(label: "Timing Mode") {
                    HUDSegmentedPicker(
                        options: [SpeedMode.clicksPerSecond, .fixedInterval, .randomRange],
                        selection: Binding(
                            get: {
                                profile.wrappedValue.speed.mode == .humanized
                                    ? .clicksPerSecond : profile.wrappedValue.speed.mode
                            },
                            set: { profile.wrappedValue.speed.mode = $0 }),
                        label: { $0.displayName })
                }
                switch profile.wrappedValue.speed.mode {
                case .clicksPerSecond, .humanized:
                    HUDSliderRow(label: "Clicks Per Second",
                                 value: profile.speed.clicksPerSecond,
                                 range: 0.1...100, unit: "cps", fractionDigits: 1,
                                 detail: "Decimal values allowed, e.g. 0.5 = one click every 2 s")
                case .fixedInterval:
                    HUDSliderRow(label: "Interval",
                                 value: profile.speed.intervalMS,
                                 range: 1...60_000, unit: "ms",
                                 detail: "Fixed delay between clicks")
                case .randomRange:
                    HUDSliderRow(label: "Minimum Interval",
                                 value: profile.speed.randomMinMS,
                                 range: 1...60_000, unit: "ms")
                    HUDSliderRow(label: "Maximum Interval",
                                 value: profile.speed.randomMaxMS,
                                 range: 1...60_000, unit: "ms",
                                 detail: "Each delay is drawn uniformly from this range")
                }
                if profile.wrappedValue.humanization.enabled {
                    Label("Humanization is enabled — it overrides this timing with the humanized generator.",
                          systemImage: "waveform.path.ecg")
                        .font(.system(size: 10.5))
                        .foregroundStyle(style.palette.warning)
                }
            }

            HStack(spacing: 14) {
                HUDStat(label: "Estimated Rate",
                        value: String(format: "%.1f cps", profile.wrappedValue.estimatedCPS),
                        color: style.accent)
                HUDStat(label: "Avg Interval",
                        value: profile.wrappedValue.estimatedCPS > 0
                            ? String(format: "%.0f ms", 1000 / profile.wrappedValue.estimatedCPS) : "—")
                if profile.wrappedValue.estimatedCPS > SpeedConfig.highRateThresholdCPS {
                    StatusIndicator(state: .warning, label: "High rate — confirmation required at start")
                }
            }
        }
        .hudPanel()
    }

    // MARK: Validation

    @ViewBuilder
    private func validationPanel(_ profile: Profile) -> some View {
        let issues = profile.validationIssues()
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HUDSectionHeader(title: "Configuration Issues", systemImage: "exclamationmark.triangle")
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "xmark.octagon.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.danger)
                }
                Text("The engine refuses to start while these issues exist.")
                    .font(.system(size: 10))
                    .foregroundStyle(style.palette.textDim)
            }
            .hudPanel()
        }
    }
}
