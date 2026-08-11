import Foundation
import Combine

/// Global, non-profile settings: appearance, sounds, menu bar, emergency
/// stop shortcut. Persisted as JSON next to the profiles.
struct AppSettings: Codable, Equatable {
    // Appearance
    var themeID: String = HUDThemeID.neonCyan.rawValue
    /// 0…1 multiplier on all glow effects.
    var glowIntensity: Double = 0.7
    /// 0…1 multiplier on non-essential animation.
    var animationIntensity: Double = 0.8
    var showGrid: Bool = true
    var showScanlines: Bool = true
    var showParticles: Bool = true
    /// 0.8…1.4 interface scale.
    var interfaceScale: Double = 1.0
    var compactLayout: Bool = false

    // Behavior
    var soundsEnabled: Bool = false
    var showMenuBarItem: Bool = true
    var keepRunningWhenWindowCloses: Bool = true

    // Safety (global)
    var emergencyStop: KeyboardShortcut = .defaultEmergencyStop
    /// Re-arm the global trigger automatically on launch if it was armed
    /// when the app last quit. Clicking still only starts when the user
    /// presses their assigned trigger, and the emergency stop always works.
    var rememberArmedState: Bool = true
    /// Persisted armed state (only applied when `rememberArmedState` is on).
    var wasArmed: Bool = false

    func sanitized() -> AppSettings {
        var copy = self
        copy.glowIntensity = glowIntensity.clamped(to: 0...1)
        copy.animationIntensity = animationIntensity.clamped(to: 0...1)
        copy.interfaceScale = interfaceScale.clamped(to: 0.8...1.4)
        if HUDThemeID(rawValue: copy.themeID) == nil {
            copy.themeID = HUDThemeID.neonCyan.rawValue
        }
        return copy
    }
}

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("settings.json") }
    private let saveQueue = DispatchQueue(label: "com.autoclicker.settings-store", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    init(directory: URL? = nil) {
        let dir = directory ?? ProfileStore.defaultDirectory()
        self.directory = dir
        let url = dir.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded.sanitized()
        } else {
            settings = AppSettings()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = settings
        let url = fileURL
        let dir = directory
        let item = DispatchWorkItem {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                NSLog("Autoclicker: failed to save settings: \(error)")
            }
        }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let snapshot = settings
        let url = fileURL
        let dir = directory
        saveQueue.sync {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                NSLog("Autoclicker: failed to save settings: \(error)")
            }
        }
    }
}
