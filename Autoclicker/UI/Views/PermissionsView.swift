import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissions: PermissionManager
    @Environment(\.hudStyle) private var style

    var body: some View {
        HUDScreen(title: "Permissions",
                  subtitle: "macOS privacy permissions the app needs. Status re-checks automatically when you return from System Settings.") {
            overviewStrip

            permissionCard(
                title: "Accessibility",
                status: permissions.accessibility,
                required: true,
                why: "Required to create the global event tap that detects your trigger input (including Mouse Button 3/4), to optionally suppress trigger events, and to post the synthesized mouse clicks themselves. Without it the app cannot click at all.",
                request: { permissions.requestAccessibility() },
                openSettings: { permissions.openAccessibilitySettings() })

            permissionCard(
                title: "Input Monitoring",
                status: permissions.inputMonitoring,
                required: false,
                why: "Needed on some systems for global keyboard capture — keyboard triggers, the emergency-stop shortcut while other apps are frontmost, and key display in Input Detection mode. Mouse-only use may work with Accessibility alone.",
                request: { permissions.requestInputMonitoring() },
                openSettings: { permissions.openInputMonitoringSettings() })

            failSafePanel
        }
    }

    private var overviewStrip: some View {
        HStack(spacing: 18) {
            StatusIndicator(
                state: permissions.accessibility.isGranted ? .good : .bad,
                label: "Accessibility")
            StatusIndicator(
                state: permissions.inputMonitoring.isGranted ? .good : .warning,
                label: "Input Monitoring")
            StatusIndicator(
                state: appState.monitor.isMonitoring ? .good : .neutral,
                label: "Event Tap Active")
            StatusIndicator(
                state: appState.monitor.canSuppress ? .good : .neutral,
                label: "Suppression Available")
            Spacer()
            Button {
                permissions.refresh()
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(HUDButtonStyle())
        }
        .hudPanel()
    }

    private func permissionCard(
        title: String,
        status: PermissionManager.Status,
        required: Bool,
        why: String,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: status.isGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(status.isGranted ? style.palette.good
                        : required ? style.palette.danger : style.palette.warning)
                    .shadow(color: (status.isGranted ? style.palette.good : style.palette.danger)
                        .opacity(0.5 * style.glow), radius: style.glowRadius(6))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(style.palette.textPrimary)
                        Text(required ? "REQUIRED" : "RECOMMENDED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(required ? style.palette.danger : style.palette.warning)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(Capsule().stroke(
                                (required ? style.palette.danger : style.palette.warning).opacity(0.5),
                                lineWidth: 1))
                    }
                    Text(status.isGranted ? "Granted" : status == .denied ? "Not granted" : "Unknown")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(status.isGranted ? style.palette.good : style.palette.textDim)
                }
                Spacer()
            }
            Text(why)
                .font(.system(size: 11))
                .foregroundStyle(style.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !status.isGranted {
                HStack(spacing: 8) {
                    Button("Request Access") { request() }
                        .buttonStyle(HUDButtonStyle(prominent: true))
                    Button {
                        openSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(HUDButtonStyle())
                }
                Text("If the app doesn't appear in the list, add it with the “+” button. After changing the permission, macOS may require relaunching the app.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(style.palette.textDim)
                if required {
                    Label("Building from Xcode? Ad-hoc-signed builds get a new signature on every build, which silently invalidates this grant even though the checkbox still shows “on”. Sign with a Team (Signing & Capabilities) for a stable identity, or reset with:  tccutil reset Accessibility com.sambesley.Autoclicker",
                          systemImage: "hammer")
                        .font(.system(size: 9.5))
                        .foregroundStyle(style.palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .hudPanel(accented: !status.isGranted && required)
    }

    private var failSafePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDSectionHeader(title: "Fail-Safe Behavior", systemImage: "shield.lefthalf.filled")
            ForEach([
                "With permissions missing, all clicking functions are disabled — the app never attempts blind event posting.",
                "If a permission is revoked while a session runs, the session stops immediately and the trigger disarms.",
                "The global event tap is torn down whenever it cannot operate, never left dangling.",
            ], id: \.self) { line in
                Label(line, systemImage: "checkmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.palette.textDim)
            }
        }
        .hudPanel()
    }
}
