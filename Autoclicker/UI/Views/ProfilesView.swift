import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Shared helper: two-way binding into the selected profile.
extension AppState {
    var selectedProfileBinding: Binding<Profile>? {
        guard let current = selectedProfile else { return nil }
        return Binding(
            get: { [weak self] in self?.selectedProfile ?? current },
            set: { [weak self] newValue in
                self?.updateSelectedProfile { $0 = newValue }
            })
    }
}

struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.hudStyle) private var style

    @State private var renamingID: UUID? = nil
    @State private var renameText = ""
    @State private var importError: String? = nil
    @State private var confirmRestore = false

    var body: some View {
        HUDScreen(title: "Profiles",
                  subtitle: "Each profile stores a complete configuration: trigger, mode, speed, targeting, humanization, sequence and safety.") {
            VStack(alignment: .leading, spacing: 10) {
                toolbar
                VStack(spacing: 6) {
                    ForEach(profileStore.profiles) { profile in
                        profileRow(profile)
                    }
                }
                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.danger)
                }
            }
            .hudPanel()
        }
        .confirmationDialog("Replace all profiles with the default presets?",
                            isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) {
                profileStore.restoreDefaults()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { _ = profileStore.createProfile() } label: {
                Label("New", systemImage: "plus")
            }
            Button {
                if let profile = profileStore.selectedProfile {
                    _ = profileStore.duplicate(profile)
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(profileStore.selectedProfile == nil)
            Spacer()
            Button(action: importProfile) { Label("Import", systemImage: "square.and.arrow.down") }
            Button(action: exportProfile) { Label("Export", systemImage: "square.and.arrow.up") }
                .disabled(profileStore.selectedProfile == nil)
            Button { confirmRestore = true } label: {
                Label("Defaults", systemImage: "arrow.counterclockwise")
            }
        }
        .buttonStyle(HUDButtonStyle())
    }

    private func profileRow(_ profile: Profile) -> some View {
        let selected = profile.id == profileStore.selectedProfileID
        let accent = HUDThemeID(rawValue: profile.accentThemeID ?? "")?.palette.accent ?? style.accent
        return HStack(spacing: 10) {
            Rectangle()
                .fill(accent)
                .frame(width: 3, height: 26)
                .shadow(color: accent.opacity(0.8 * style.glow), radius: style.glowRadius(4))
            VStack(alignment: .leading, spacing: 1) {
                if renamingID == profile.id {
                    TextField("Name", text: $renameText, onCommit: {
                        profileStore.rename(profile.id, to: renameText)
                        renamingID = nil
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                } else {
                    Text(profile.name)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(style.palette.textPrimary)
                }
                Text("\(profile.mode.displayName) · \(profile.trigger.displayName) · \(String(format: "%.1f", profile.estimatedCPS)) cps")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(style.palette.textDim)
            }
            Spacer()
            if selected {
                Text("ACTIVE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(AngularPanel(cut: 4).stroke(accent.opacity(0.6), lineWidth: 1))
            }
            Menu {
                Button("Rename") {
                    renameText = profile.name
                    renamingID = profile.id
                }
                Button("Duplicate") { _ = profileStore.duplicate(profile) }
                Divider()
                Button("Delete", role: .destructive) { profileStore.delete(profile.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(style.palette.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .accessibilityLabel("Profile actions for \(profile.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            AngularPanel(cut: 8)
                .fill(selected ? accent.opacity(0.08) : Color.white.opacity(0.025))
                .overlay(AngularPanel(cut: 8).stroke(
                    selected ? accent.opacity(0.55) : Color.white.opacity(0.07), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { appState.selectProfile(profile.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)\(selected ? ", active" : "")")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: JSON import / export

    private func importProfile() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Autoclicker profile JSON file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try profileStore.importProfile(from: data)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportProfile() {
        guard let profile = profileStore.selectedProfile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        panel.message = "Export the selected profile as JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try profileStore.exportData(for: profile).write(to: url)
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }
}
