import Foundation

/// Pure state machine mapping trigger presses/releases to engine commands.
/// Keeping this free of threads and side effects makes every activation mode
/// unit-testable.
struct TriggerStateMachine {
    enum Event: Equatable {
        case triggerPressed
        case triggerReleased
        case emergencyStop
        /// The engine reported that a self-terminating session (burst,
        /// one-shot, limits) finished on its own.
        case sessionEnded
    }

    enum Command: Equatable {
        case none
        /// Start a continuous session (hold / toggle / humanized rapid /
        /// repeat sequence).
        case startContinuous
        /// Start a self-terminating burst of the configured click count.
        case startBurst
        /// Start a single one-shot action or sequence pass.
        case startOneShot
        case stop(StopReason)
    }

    private(set) var mode: ActivationMode
    private(set) var isActive = false

    init(mode: ActivationMode) {
        self.mode = mode
    }

    mutating func setMode(_ newMode: ActivationMode) {
        mode = newMode
    }

    mutating func handle(_ event: Event) -> Command {
        // Emergency stop always wins, in every mode, in every state.
        if event == .emergencyStop {
            let wasActive = isActive
            isActive = false
            return wasActive ? .stop(.emergencyStop) : .none
        }

        switch event {
        case .sessionEnded:
            isActive = false
            return .none

        case .triggerPressed:
            switch mode {
            case .hold:
                if isActive { return .none } // key-repeat / duplicate press
                isActive = true
                return .startContinuous
            case .toggle, .humanizedRapid, .repeatSequence:
                if isActive {
                    isActive = false
                    return .stop(.userRequested)
                }
                isActive = true
                return .startContinuous
            case .burst:
                if isActive { return .none } // ignore rapid re-presses mid-burst
                isActive = true
                return .startBurst
            case .oneShot:
                if isActive { return .none }
                isActive = true
                return .startOneShot
            }

        case .triggerReleased:
            switch mode {
            case .hold:
                if isActive {
                    isActive = false
                    return .stop(.triggerReleased)
                }
                return .none
            default:
                return .none
            }

        case .emergencyStop:
            return .none // handled above
        }
    }
}
