import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard, profiles, trigger, clickEngine, sequence, targeting
    case humanization, safety, appearance, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .profiles: return "Profiles"
        case .trigger: return "Trigger"
        case .clickEngine: return "Click Engine"
        case .sequence: return "Sequence"
        case .targeting: return "Targeting"
        case .humanization: return "Humanization"
        case .safety: return "Safety"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .profiles: return "person.crop.rectangle.stack"
        case .trigger: return "scope"
        case .clickEngine: return "bolt.horizontal.circle"
        case .sequence: return "list.number"
        case .targeting: return "target"
        case .humanization: return "waveform.path.ecg"
        case .safety: return "shield.lefthalf.filled"
        case .appearance: return "paintbrush.pointed"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: SidebarSection = .dashboard

    var body: some View {
        let style = HUDStyle.make(
            settings: settingsStore.settings,
            profileThemeID: appState.selectedProfile?.accentThemeID,
            reduceMotion: reduceMotion,
            appActive: appState.isAppActive)
        let scale = settingsStore.settings.interfaceScale

        GeometryReader { geo in
            content
                .environment(\.hudStyle, style)
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .preferredColorScheme(.dark)
        .alert("High click rate", isPresented: $appState.pendingHighRateStart) {
            Button("Start Anyway") { appState.confirmHighRateAndStart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This profile is configured for more than \(Int(SpeedConfig.highRateThresholdCPS)) clicks per second. Very high rates can make the system hard to control — remember the emergency stop: \(appState.emergencyStopDisplay)")
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .overlay(Color.white.opacity(0.06))
            detail
        }
        .background(HUDBackground())
    }

    private var sidebar: some View {
        SidebarColumn(section: $section)
            .frame(width: 210)
    }

    private var detail: some View {
        Group {
            switch section {
            case .dashboard: DashboardView(section: $section)
            case .profiles: ProfilesView()
            case .trigger: TriggerView()
            case .clickEngine: ClickEngineView()
            case .sequence: SequenceEditorView()
            case .targeting: TargetingView()
            case .humanization: HumanizationView()
            case .safety: SafetyView()
            case .appearance: AppearanceView()
            case .permissions: PermissionsView()
            case .about: AboutView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SidebarColumn: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style
    @Binding var section: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            VStack(alignment: .leading, spacing: 2) {
                Text("AUTOCLICKER")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(style.accent)
                    .shadow(color: style.accent.opacity(0.7 * style.glow), radius: style.glowRadius(8))
                Text("CYBERNETIC INPUT CONSOLE")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(style.palette.textDim)
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Autoclicker")

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarSection.allCases) { item in
                        SidebarButton(item: item, selected: section == item) {
                            section = item
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // Persistent footer: state + emergency stop reminder.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    PulsingDot(active: appState.isRunning)
                    Text(appState.isRunning ? "RUNNING" : (appState.isArmed ? "ARMED" : "STANDBY"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(appState.isRunning ? style.palette.good
                            : appState.isArmed ? style.accent : style.palette.textDim)
                }
                Text("E-STOP  \(appState.emergencyStopDisplay)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(style.palette.textDim)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SidebarButton: View {
    @Environment(\.hudStyle) private var style
    var item: SidebarSection
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? style.accent : style.palette.textSecondary)
                Text(item.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? style.palette.textPrimary : style.palette.textSecondary)
                Spacer()
                if selected {
                    Rectangle()
                        .fill(style.accent)
                        .frame(width: 2, height: 14)
                        .shadow(color: style.accent.opacity(0.8 * style.glow), radius: style.glowRadius(4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                AngularPanel(cut: 7)
                    .fill(selected ? style.accent.opacity(0.1)
                          : hovering ? Color.white.opacity(0.045) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(style.animationsEnabled ? .easeOut(duration: 0.12) : nil, value: hovering)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Shared scroll container for the detail screens.
struct HUDScreen<Content: View>: View {
    @Environment(\.hudStyle) private var style
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(style.palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(style.palette.textSecondary)
                    }
                }
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }
}

/// Shown by editor screens when no profile is selected (empty store edge).
struct NoProfilePlaceholder: View {
    @Environment(\.hudStyle) private var style

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(style.palette.textDim)
            Text("No profile selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
