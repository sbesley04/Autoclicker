import Foundation
import CoreGraphics

/// A mouse button, using CoreGraphics button numbering:
/// 0 = left, 1 = right, 2 = middle, 3+ = "other" buttons (Mouse Button 3, 4, …).
enum MouseButton: Hashable, Codable {
    case left
    case right
    case middle
    case other(Int)

    init(buttonNumber: Int) {
        switch buttonNumber {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: self = .other(buttonNumber)
        }
    }

    var buttonNumber: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .other(let n): return n
        }
    }

    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        default: return CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
        }
    }

    var downEventType: CGEventType {
        switch self {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        default: return .otherMouseDown
        }
    }

    var upEventType: CGEventType {
        switch self {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        default: return .otherMouseUp
        }
    }

    /// Human-readable name. Buttons ≥ 2 are commonly labeled "Mouse Button N"
    /// where N = buttonNumber + 1 in most vendor software; we show both.
    var displayName: String {
        switch self {
        case .left: return "Left Button"
        case .right: return "Right Button"
        case .middle: return "Middle Button"
        case .other(let n): return "Mouse Button \(n) (#\(n))"
        }
    }
}

/// What kind of click the engine performs on each cycle.
enum ClickType: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case middle
    case double
    case mouseDownOnly
    case mouseUpOnly
    case clickAndHold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .double: return "Double Click"
        case .mouseDownOnly: return "Mouse Down Only"
        case .mouseUpOnly: return "Mouse Up Only"
        case .clickAndHold: return "Click & Hold"
        }
    }

    var button: MouseButton {
        switch self {
        case .right: return .right
        case .middle: return .middle
        default: return .left
        }
    }

    var systemImage: String {
        switch self {
        case .left: return "cursorarrow.click"
        case .right: return "cursorarrow.click.2"
        case .middle: return "cursorarrow.click.badge.clock"
        case .double: return "cursorarrow.rays"
        case .mouseDownOnly: return "arrow.down.circle"
        case .mouseUpOnly: return "arrow.up.circle"
        case .clickAndHold: return "hand.tap"
        }
    }
}

/// How the trigger input activates the engine.
enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle
    case burst
    case oneShot
    case repeatSequence
    case humanizedRapid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Hold"
        case .toggle: return "Toggle"
        case .burst: return "Burst"
        case .oneShot: return "One-Shot"
        case .repeatSequence: return "Repeat Sequence"
        case .humanizedRapid: return "Humanized Rapid"
        }
    }

    var summary: String {
        switch self {
        case .hold: return "Clicks while the trigger is held down"
        case .toggle: return "Press to start, press again to stop"
        case .burst: return "Each press fires a fixed number of clicks"
        case .oneShot: return "One press performs one action or sequence"
        case .repeatSequence: return "Repeats the action sequence until stopped"
        case .humanizedRapid: return "Continuous clicking with natural timing variation"
        }
    }

    var systemImage: String {
        switch self {
        case .hold: return "hand.point.up.left.fill"
        case .toggle: return "togglepower"
        case .burst: return "bolt.fill"
        case .oneShot: return "1.circle"
        case .repeatSequence: return "arrow.triangle.2.circlepath"
        case .humanizedRapid: return "waveform.path.ecg"
        }
    }

    /// Modes whose sessions run until explicitly stopped (vs. self-terminating).
    var isContinuous: Bool {
        switch self {
        case .hold, .toggle, .humanizedRapid, .repeatSequence: return true
        case .burst, .oneShot: return false
        }
    }
}

/// What happens to the physical input event that acts as the trigger.
enum InputBehavior: String, Codable, CaseIterable, Identifiable {
    /// The event reaches other apps normally in addition to triggering.
    case passThrough
    /// The event is swallowed whenever it matches the trigger (requires an
    /// active event tap, i.e. Accessibility permission).
    case suppress
    /// Like suppress, but only while it is acting as a trigger; non-trigger
    /// state changes pass through. In practice identical to suppress for
    /// button triggers; kept distinct for clarity in the UI.
    case triggerOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passThrough: return "Pass Through"
        case .suppress: return "Suppress"
        case .triggerOnly: return "Trigger Only"
        }
    }

    var summary: String {
        switch self {
        case .passThrough: return "The original click/key also reaches other apps"
        case .suppress: return "The original event is swallowed while assigned"
        case .triggerOnly: return "The event only acts as a trigger and is swallowed"
        }
    }

    var wantsSuppression: Bool { self != .passThrough }
}

/// Why a clicking session stopped — surfaced in the UI and used by tests.
enum StopReason: Equatable {
    case userRequested
    case triggerReleased
    case emergencyStop
    case maxClicksReached
    case maxRuntimeReached
    case permissionsLost
    case appSwitched
    case appTerminating
    case sequenceCompleted
    case systemSleep
    case error(String)

    var displayName: String {
        switch self {
        case .userRequested: return "Stopped"
        case .triggerReleased: return "Trigger released"
        case .emergencyStop: return "EMERGENCY STOP"
        case .maxClicksReached: return "Click limit reached"
        case .maxRuntimeReached: return "Runtime limit reached"
        case .permissionsLost: return "Permissions revoked"
        case .appSwitched: return "Active app changed"
        case .appTerminating: return "App quitting"
        case .sequenceCompleted: return "Sequence complete"
        case .systemSleep: return "System sleep"
        case .error(let message): return "Error: \(message)"
        }
    }
}
