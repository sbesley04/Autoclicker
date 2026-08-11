import Foundation
import AppKit

/// Optional HUD sound effects, mapped onto system-provided sounds so no
/// bundled (or copyrighted) audio assets are needed. Disabled by default via
/// AppSettings.soundsEnabled.
final class SoundManager {
    enum Effect {
        case start, stop, toggle, error, countdownTick, profileSwitch

        /// Names of sounds shipped with macOS (/System/Library/Sounds).
        var systemSoundName: NSSound.Name {
            switch self {
            case .start: return "Morse"
            case .stop: return "Bottle"
            case .toggle: return "Pop"
            case .error: return "Basso"
            case .countdownTick: return "Tink"
            case .profileSwitch: return "Purr"
            }
        }
    }

    /// Read on every play so toggling the setting applies instantly.
    var isEnabled: () -> Bool = { false }

    func play(_ effect: Effect) {
        guard isEnabled() else { return }
        if let sound = NSSound(named: effect.systemSoundName) {
            sound.volume = 0.4
            sound.play()
        }
    }
}
