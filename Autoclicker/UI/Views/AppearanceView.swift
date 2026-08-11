import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.hudStyle) private var style

    private var settings: Binding<AppSettings> {
        Binding(
            get: { settingsStore.settings },
            set: { settingsStore.settings = $0.sanitized() })
    }

    var body: some View {
        HUDScreen(title: "Appearance",
                  subtitle: "Themes, glow, motion and layout. Reduce Motion in System Settings always overrides animation here.") {
            themePanel
            effectsPanel
            layoutPanel
            behaviorPanel
        }
    }

    // MARK: Themes

    private var themePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Theme", systemImage: "paintpalette")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(HUDThemeID.allCases) { theme in
                    themeCard(theme)
                }
            }
            if let profile = appState.selectedProfile {
                HUDRow(label: "Profile accent override",
                       detail: "Give “\(profile.name)” its own accent color") {
                    Menu {
                        Button("Use App Theme") {
                            appState.updateSelectedProfile { $0.accentThemeID = nil }
                        }
                        Divider()
                        ForEach(HUDThemeID.allCases) { theme in
                            Button(theme.displayName) {
                                appState.updateSelectedProfile { $0.accentThemeID = theme.rawValue }
                            }
                        }
                    } label: {
                        Text(profile.accentThemeID.flatMap { HUDThemeID(rawValue: $0)?.displayName } ?? "App Theme")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(style.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .hudPanel()
    }

    private func themeCard(_ theme: HUDThemeID) -> some View {
        let selected = settingsStore.settings.themeID == theme.rawValue
        let palette = theme.palette
        return Button {
            settingsStore.settings.themeID = theme.rawValue
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(palette.accent).frame(width: 14, height: 14)
                        .shadow(color: palette.accent.opacity(0.8), radius: 4)
                    Circle().fill(palette.secondary).frame(width: 10, height: 10)
                }
                Text(theme.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(selected ? style.palette.textPrimary : style.palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                AngularPanel(cut: 7)
                    .fill(selected ? palette.accent.opacity(0.1) : Color.white.opacity(0.03))
                    .overlay(AngularPanel(cut: 7).stroke(
                        selected ? palette.accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Effects

    private var effectsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Effects", systemImage: "sparkles")
            HUDSliderRow(label: "Glow Intensity",
                         value: settings.glowIntensity,
                         range: 0...1, fractionDigits: 2)
            HUDSliderRow(label: "Animation Intensity",
                         value: settings.animationIntensity,
                         range: 0...1, fractionDigits: 2,
                         detail: "0 disables non-essential motion entirely")
            HUDRow(label: "Background Grid") {
                Toggle(isOn: settings.showGrid) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Show background grid")
            }
            HUDRow(label: "Scan Lines") {
                Toggle(isOn: settings.showScanlines) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Show scan lines")
            }
            HUDRow(label: "Ambient Particles") {
                Toggle(isOn: settings.showParticles) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Show ambient particles")
            }
        }
        .hudPanel()
    }

    // MARK: Layout

    private var layoutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Layout", systemImage: "rectangle.3.group")
            HUDSliderRow(label: "Interface Scale",
                         value: settings.interfaceScale,
                         range: 0.8...1.4, fractionDigits: 2)
            HUDRow(label: "Compact Layout",
                   detail: "Tighter panel padding for smaller windows") {
                Toggle(isOn: settings.compactLayout) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Compact layout")
            }
        }
        .hudPanel()
    }

    // MARK: Behavior

    private var behaviorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Sound & System", systemImage: "speaker.wave.2")
            HUDRow(label: "HUD Sound Effects",
                   detail: "Subtle system sounds for start, stop, errors and countdowns") {
                Toggle(isOn: settings.soundsEnabled) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Enable sound effects")
            }
            HUDRow(label: "Menu Bar Item",
                   detail: "Quick controls in the macOS menu bar") {
                Toggle(isOn: settings.showMenuBarItem) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Show menu bar item")
            }
            HUDRow(label: "Keep Running When Window Closes",
                   detail: "The app (and menu bar item) stays alive without the main window") {
                Toggle(isOn: settings.keepRunningWhenWindowCloses) { EmptyView() }
                    .toggleStyle(HUDToggleStyle())
                    .accessibilityLabel("Keep running when window closes")
            }
        }
        .hudPanel()
    }
}
