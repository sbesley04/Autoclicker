import SwiftUI
import AppKit

struct TargetingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style
    @State private var newlyCapturedID: UUID? = nil

    var body: some View {
        HUDScreen(title: "Targeting",
                  subtitle: "Where clicks land: the live cursor position or saved screen coordinates.") {
            if let profile = appState.selectedProfileBinding {
                modePanel(profile)
                pointsPanel(profile)
            } else {
                NoProfilePlaceholder()
            }
        }
        .onDisappear {
            if appState.isCapturingPoint { appState.cancelPointCapture() }
        }
    }

    private func modePanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HUDSectionHeader(title: "Target Mode", systemImage: "target")
            HUDSegmentedPicker(
                options: TargetingMode.allCases,
                selection: profile.targeting.mode,
                label: { $0.displayName })
            Text(profile.wrappedValue.targeting.mode.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(style.palette.textSecondary)
            Toggle(isOn: profile.targeting.returnToOrigin) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Return cursor to origin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.palette.textPrimary)
                    Text("After the session ends, move the cursor back to where it started")
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .toggleStyle(HUDToggleStyle())
        }
        .hudPanel()
    }

    private func pointsPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HUDSectionHeader(title: "Saved Coordinates", systemImage: "mappin.and.ellipse")
                if appState.isCapturingPoint {
                    Button("Cancel Capture") { appState.cancelPointCapture() }
                        .buttonStyle(HUDButtonStyle(role: .destructive))
                } else {
                    Button {
                        appState.beginPointCapture { point in
                            let captured = SavedPoint(
                                name: "Point \(profile.wrappedValue.targeting.points.count + 1)",
                                x: point.x.rounded(), y: point.y.rounded())
                            profile.wrappedValue.targeting.points.append(captured)
                            newlyCapturedID = captured.id
                        }
                    } label: {
                        Label("Capture Position", systemImage: "plus.viewfinder")
                    }
                    .buttonStyle(HUDButtonStyle(prominent: true))
                    .disabled(!appState.monitor.isMonitoring)
                }
            }

            if appState.isCapturingPoint {
                HStack(spacing: 8) {
                    PulsingDot(active: true, color: style.palette.warning)
                    Text("CAPTURE ARMED — click anywhere on any display to save that position")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(style.palette.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AngularPanel(cut: 8).stroke(style.palette.warning.opacity(0.6), lineWidth: 1))
            }

            if profile.wrappedValue.targeting.points.isEmpty {
                Text("No saved coordinates. Capture one, or add the current cursor position.")
                    .font(.system(size: 11))
                    .foregroundStyle(style.palette.textDim)
            } else {
                VStack(spacing: 4) {
                    ForEach(profile.wrappedValue.targeting.points) { point in
                        pointRow(profile, point)
                    }
                }
            }

            Button {
                let loc = ScreenCoordinates.currentMouseLocationCG()
                profile.wrappedValue.targeting.points.append(SavedPoint(
                    name: "Point \(profile.wrappedValue.targeting.points.count + 1)",
                    x: loc.x.rounded(), y: loc.y.rounded()))
            } label: {
                Label("Add Current Cursor Position", systemImage: "cursorarrow")
            }
            .buttonStyle(HUDButtonStyle())

            Text("Coordinates are stored in global display space (origin at the top-left of the main display) and work across multiple monitors and Retina scaling. If a display is disconnected, points on it will land at the nearest valid location — sessions stop automatically when the display layout changes.")
                .font(.system(size: 9.5))
                .foregroundStyle(style.palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hudPanel(accented: appState.isCapturingPoint)
    }

    private func pointRow(_ profile: Binding<Profile>, _ point: SavedPoint) -> some View {
        let screenName = ScreenCoordinates.screen(containingCG: point.cgPoint)?.localizedName
        return HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 11))
                .foregroundStyle(style.accent)
            TextField("Name", text: Binding(
                get: { point.name },
                set: { newName in
                    if let i = profile.wrappedValue.targeting.points.firstIndex(where: { $0.id == point.id }) {
                        profile.wrappedValue.targeting.points[i].name = newName
                    }
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style.palette.textPrimary)
                .frame(width: 140)
            Text("X \(Int(point.x))  Y \(Int(point.y))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(style.accent)
            if let screenName {
                Text(screenName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(style.palette.textDim)
            } else {
                StatusIndicator(state: .warning, label: "off-screen")
            }
            Spacer()
            Button {
                profile.wrappedValue.targeting.points.removeAll { $0.id == point.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(style.palette.danger.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(point.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            AngularPanel(cut: 6)
                .fill(newlyCapturedID == point.id ? style.accent.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(AngularPanel(cut: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}
