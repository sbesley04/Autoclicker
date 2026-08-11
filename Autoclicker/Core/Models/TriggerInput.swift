import Foundation

/// Keyboard modifier flags, mirrored from CGEventFlags so the model layer
/// stays free of CoreGraphics types and is trivially Codable.
struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
    static let function = KeyModifiers(rawValue: 1 << 4)

    var displaySymbols: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        if contains(.function) { parts.append("fn") }
        return parts.joined()
    }
}

/// The physical input assigned to activate a profile.
enum TriggerInput: Codable, Hashable {
    case mouseButton(number: Int)
    case keyboard(keyCode: Int, modifiers: KeyModifiers)
    case none

    var displayName: String {
        switch self {
        case .mouseButton(let n):
            return MouseButton(buttonNumber: n).displayName
        case .keyboard(let keyCode, let modifiers):
            let key = KeyCodeNames.name(for: keyCode)
            let mods = modifiers.displaySymbols
            return mods.isEmpty ? key : "\(mods) \(key)"
        case .none:
            return "Not Assigned"
        }
    }

    var isAssigned: Bool {
        if case .none = self { return false }
        return true
    }

    var isMouse: Bool {
        if case .mouseButton = self { return true }
        return false
    }
}

/// A keyboard shortcut (used for the global emergency stop).
struct KeyboardShortcut: Codable, Hashable {
    var keyCode: Int
    var modifiers: KeyModifiers

    /// Default emergency stop: ⌘⇧⎋ (Command + Shift + Escape).
    static let defaultEmergencyStop = KeyboardShortcut(
        keyCode: 53, modifiers: [.command, .shift])

    var displayName: String {
        let key = KeyCodeNames.name(for: keyCode)
        let mods = modifiers.displaySymbols
        return mods.isEmpty ? key : "\(mods)\(key)"
    }

    func matches(keyCode: Int, modifiers: KeyModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }
}

/// Virtual key code → human-readable names for the common keys.
enum KeyCodeNames {
    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "⎋", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home",
        116: "Page Up", 117: "Fwd Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func name(for keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
