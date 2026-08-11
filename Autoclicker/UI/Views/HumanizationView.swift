import SwiftUI

struct HumanizationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style
    @State private var preview: TimingPreview.Result? = nil

    var body: some View {
        HUDScreen(title: "Humanization",
                  subtitle: "Natural timing variation for Humanized Rapid mode, and an optional humanization layer for every other mode. All features are off by default.") {
            if let profile = appState.selectedProfileBinding {
                if profile.wrappedValue.mode == .humanizedRapid {
                    timingEditor(
                        title: "Humanized Rapid Timing",
                        icon: "waveform.path.ecg",
                        timing: profile.humanizedRapid,
                        showProfilePresets: false)
                } else {
                    layerTogglePanel(profile)
                    if profile.wrappedValue.humanization.enabled {
                        timingEditor(
                            title: "Humanized Timing",
                            icon: "waveform.path.ecg",
                            timing: profile.humanization.timing,
                            showProfilePresets: true)
                    }
                }
                liveVisualizationPanel
                previewPanel(activeTiming(profile.wrappedValue))
            } else {
                NoProfilePlaceholder()
            }
        }
    }

    private func activeTiming(_ profile: Profile) -> HumanizedTiming {
        profile.mode == .humanizedRapid ? profile.humanizedRapid : profile.humanization.timing
    }

    // MARK: Layer toggle

    private func layerTogglePanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "Humanization Layer", systemImage: "person.wave.2")
            Toggle(isOn: profile.humanization.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enable humanized timing for \(profile.wrappedValue.mode.displayName) mode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.palette.textPrimary)
                    Text("Replaces the fixed click speed with bounded natural variation. Also applies inside action sequences.")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .toggleStyle(HUDToggleStyle())
        }
        .hudPanel()
    }

    // MARK: Timing editor

    private func timingEditor(
        title: String, icon: String,
        timing: Binding<HumanizedTiming>,
        showProfilePresets: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: title, systemImage: icon)

            HUDRow(label: "Timing Profile",
                   detail: timing.wrappedValue.profile.summary) {
                HUDSegmentedPicker(
                    options: HumanizationProfile.allCases,
                    selection: Binding(
                        get: { timing.wrappedValue.profile },
                        set: { newProfile in
                            var t = timing.wrappedValue
                            t.applyProfile(newProfile)
                            timing.wrappedValue = t
                        }),
                    label: { $0.displayName })
            }

            HUDSliderRow(label: "Target Average Speed",
                         value: timing.targetCPS,
                         range: 0.5...50, unit: "cps", fractionDigits: 1,
                         detail: "The long-run average the generator maintains")
            HUDSliderRow(label: "Timing Variation",
                         value: timing.variationPercent,
                         range: 0...60, unit: "%",
                         detail: "Standard deviation as a percentage of the average interval")
            HUDRow(label: "Variation Intensity") {
                HUDSegmentedPicker(
                    options: VariationIntensity.allCases,
                    selection: timing.intensity,
                    label: { $0.displayName })
            }
            HUDSliderRow(label: "Minimum Interval",
                         value: timing.minIntervalMS,
                         range: 1...5000, unit: "ms",
                         detail: "Hard floor — no click can come faster than this")
            HUDSliderRow(label: "Maximum Interval",
                         value: timing.maxIntervalMS,
                         range: 1...10_000, unit: "ms",
                         detail: "Hard ceiling — pauses never exceed this")

            let isCustom = timing.wrappedValue.profile == .custom
            if isCustom || timing.wrappedValue.hesitationProbability > 0 || timing.wrappedValue.burstProbability > 0 {
                HUDSliderRow(label: "Hesitation Frequency",
                             value: Binding(
                                get: { timing.wrappedValue.hesitationProbability * 100 },
                                set: { timing.wrappedValue.hesitationProbability = $0 / 100 }),
                             range: 0...25, unit: "%", fractionDigits: 1,
                             detail: "Chance of an occasional brief longer pause")
                HUDSliderRow(label: "Burst Probability",
                             value: Binding(
                                get: { timing.wrappedValue.burstProbability * 100 },
                                set: { timing.wrappedValue.burstProbability = $0 / 100 }),
                             range: 0...40, unit: "%", fractionDigits: 1,
                             detail: "Chance of entering a short rapid group of clicks")
                HUDSliderRow(label: "Burst Length",
                             value: Binding(
                                get: { Double(timing.wrappedValue.burstLength) },
                                set: { timing.wrappedValue.burstLength = Int($0) }),
                             range: 2...20,
                             detail: "Clicks per rapid burst")
            }

            HUDSliderRow(label: "Cursor Jitter",
                         value: timing.cursorJitterRadius,
                         range: 0...30, unit: "pt",
                         detail: "Slight random offset of each click position (0 = off)")

            seedRow(timing)

            let issues = timing.wrappedValue.validationIssues()
            if issues.isEmpty {
                HStack(spacing: 16) {
                    HUDStat(label: "Estimated Avg",
                            value: String(format: "%.1f cps", timing.wrappedValue.targetCPS),
                            color: style.accent)
                    HUDStat(label: "Mean Interval",
                            value: String(format: "%.0f ms", timing.wrappedValue.meanIntervalMS))
                    HUDStat(label: "Bounds",
                            value: "\(Int(timing.wrappedValue.minIntervalMS))–\(Int(timing.wrappedValue.maxIntervalMS)) ms")
                }
            } else {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "xmark.octagon.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.danger)
                }
            }
        }
        .hudPanel()
    }

    private func seedRow(_ timing: Binding<HumanizedTiming>) -> some View {
        HUDRow(label: "Random Seed",
               detail: "Set a seed for exactly reproducible timing patterns; leave off for true randomness") {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { timing.wrappedValue.seed != nil },
                    set: { timing.wrappedValue.seed = $0 ? 42 : nil })) {
                    EmptyView()
                }
                .toggleStyle(HUDToggleStyle())
                .accessibilityLabel("Use seeded randomness")
                if timing.wrappedValue.seed != nil {
                    HUDNumberField(
                        value: Binding(
                            get: { Double(timing.wrappedValue.seed ?? 42) },
                            set: { timing.wrappedValue.seed = UInt64(max(0, $0)) }),
                        range: 0...9_999_999)
                }
            }
        }
    }

    // MARK: Live visualization

    private var liveVisualizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Live Timing Telemetry", systemImage: "waveform")
            if appState.isRunning || appState.stats.totalCount > 0 {
                HStack(spacing: 16) {
                    HUDStat(label: "Current CPS",
                            value: String(format: "%.1f", appState.stats.currentCPS),
                            color: appState.isRunning ? style.accent : nil)
                    HUDStat(label: "Rolling Avg",
                            value: String(format: "%.1f", appState.stats.rollingAverageCPS))
                    HUDStat(label: "Last Interval",
                            value: appState.stats.lastInterval.map { String(format: "%.0f ms", $0 * 1000) } ?? "—")
                    HUDStat(label: "Variation σ",
                            value: String(format: "%.0f ms", appState.stats.recentVariation * 1000))
                    HUDStat(label: "Min / Max",
                            value: appState.stats.totalCount > 0
                                ? String(format: "%.0f / %.0f ms",
                                         appState.stats.minObserved * 1000,
                                         appState.stats.maxObserved * 1000)
                                : "—")
                }
                IntervalWaveform(intervals: appState.stats.recentIntervals)
                    .frame(height: 90)
            } else {
                Text("Start a session to see per-click interval telemetry here.")
                    .font(.system(size: 11))
                    .foregroundStyle(style.palette.textDim)
            }
        }
        .hudPanel(accented: appState.isRunning)
    }

    // MARK: Preview (no real clicks)

    private func previewPanel(_ timing: HumanizedTiming) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HUDSectionHeader(title: "Pattern Preview", systemImage: "chart.bar.doc.horizontal")
                Button {
                    preview = TimingPreview.simulate(config: timing, count: 120)
                } label: {
                    Label("Simulate 120 Intervals", systemImage: "play.circle")
                }
                .buttonStyle(HUDButtonStyle())
            }
            Text("Pure simulation of the timing generator — no mouse events are created.")
                .font(.system(size: 10))
                .foregroundStyle(style.palette.textDim)
            if let preview {
                HStack(spacing: 16) {
                    HUDStat(label: "Simulated Avg",
                            value: String(format: "%.2f cps", preview.averageCPS),
                            color: style.accent)
                    HUDStat(label: "Mean Interval",
                            value: String(format: "%.0f ms", preview.averageInterval * 1000))
                    HUDStat(label: "Min",
                            value: String(format: "%.0f ms", preview.minInterval * 1000))
                    HUDStat(label: "Max",
                            value: String(format: "%.0f ms", preview.maxInterval * 1000))
                }
                IntervalWaveform(intervals: preview.intervals)
                    .frame(height: 90)
            }
        }
        .hudPanel()
    }
}

// MARK: - Interval waveform

/// Bar-style timeline of recent click intervals.
struct IntervalWaveform: View {
    @Environment(\.hudStyle) private var style
    var intervals: [TimeInterval]

    var body: some View {
        Canvas { context, size in
            guard !intervals.isEmpty else { return }
            let maxValue = max(intervals.max() ?? 1, 0.001)
            let count = intervals.count
            let barWidth = max(1.5, size.width / CGFloat(count) - 1.5)
            let mean = intervals.reduce(0, +) / Double(count)

            // Mean line.
            let meanY = size.height * (1 - CGFloat(mean / maxValue))
            var meanPath = Path()
            meanPath.move(to: CGPoint(x: 0, y: meanY))
            meanPath.addLine(to: CGPoint(x: size.width, y: meanY))
            context.stroke(meanPath, with: .color(style.secondary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            for (i, interval) in intervals.enumerated() {
                let h = max(2, size.height * CGFloat(interval / maxValue))
                let x = size.width * CGFloat(i) / CGFloat(count)
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                let deviation = abs(interval - mean) / max(mean, 0.001)
                let color = style.accent.opacity(0.35 + min(deviation, 1) * 0.6)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .background(
            AngularPanel(cut: 8).fill(Color.black.opacity(0.35))
                .overlay(AngularPanel(cut: 8).stroke(style.accent.opacity(0.25), lineWidth: 1))
        )
        .accessibilityLabel("Timeline of recent click intervals")
        .accessibilityValue(intervals.isEmpty ? "no data" :
            String(format: "average %.0f milliseconds over %d clicks",
                   (intervals.reduce(0, +) / Double(intervals.count)) * 1000, intervals.count))
    }
}
