import Foundation
import CoreGraphics

/// Executes one pass of an action sequence on the engine worker thread.
/// All waiting goes through the engine's interruptible `pause` closure so an
/// emergency stop cuts through `wait` and `randomDelay` actions instantly.
final class SequenceRunner {
    /// Minimal gap inserted between consecutive non-wait actions so a
    /// sequence of bare clicks can't machine-gun at an unbounded rate.
    static let defaultGapSeconds: TimeInterval = 0.02

    private let poster: EventPosting
    private let rng: RandomSource
    private let origin: CGPoint
    /// Interruptible wait; returns false when the session must end.
    private let pause: (TimeInterval) -> Bool
    /// Supplies the implicit inter-action gap (humanized when enabled).
    private let interActionInterval: () -> TimeInterval
    private let onClick: (TimeInterval) -> Void
    private let limitsAllow: () -> Bool
    private let publishHeldButtons: ([MouseButton]) -> Void

    private var held: [MouseButton] = [] {
        didSet { publishHeldButtons(held) }
    }

    init(
        poster: EventPosting,
        rng: RandomSource,
        origin: CGPoint,
        pause: @escaping (TimeInterval) -> Bool,
        interActionInterval: @escaping () -> TimeInterval,
        onClick: @escaping (TimeInterval) -> Void,
        limitsAllow: @escaping () -> Bool,
        heldButtons: @escaping ([MouseButton]) -> Void
    ) {
        self.poster = poster
        self.rng = rng
        self.origin = origin
        self.pause = pause
        self.interActionInterval = interActionInterval
        self.onClick = onClick
        self.limitsAllow = limitsAllow
        self.publishHeldButtons = heldButtons
    }

    /// Runs one pass over the steps. Returns false when interrupted or a
    /// limit was hit.
    func runPass(_ steps: [SequenceStep]) -> Bool {
        for (index, step) in steps.enumerated() {
            guard limitsAllow() else { return false }
            guard perform(step.action) else { return false }
            // Insert the implicit gap unless this or the next action already
            // controls timing explicitly.
            if index < steps.count - 1,
               !isTimingAction(step.action),
               !isTimingAction(steps[index + 1].action) {
                guard pause(interActionInterval()) else { return false }
            }
        }
        return true
    }

    private func isTimingAction(_ action: SequenceAction) -> Bool {
        switch action {
        case .wait, .randomDelay: return true
        default: return false
        }
    }

    private func perform(_ action: SequenceAction) -> Bool {
        switch action {
        case .leftClick:
            poster.click(.left, at: poster.currentLocation)
            onClick(0)
        case .rightClick:
            poster.click(.right, at: poster.currentLocation)
            onClick(0)
        case .middleClick:
            poster.click(.middle, at: poster.currentLocation)
            onClick(0)
        case .doubleClick:
            poster.click(.left, at: poster.currentLocation, clickCount: 2)
            onClick(0)
        case .wait(let ms):
            return pause(ms / 1000)
        case .randomDelay(let minMS, let maxMS):
            let lo = max(0, minMS), hi = max(lo, maxMS)
            return pause(rng.uniform(in: lo...hi) / 1000)
        case .moveCursor(let x, let y):
            poster.moveCursor(to: CGPoint(x: x, y: y))
        case .mouseDown(let buttonNumber):
            let button = MouseButton(buttonNumber: buttonNumber)
            poster.mouseDown(button, at: poster.currentLocation, clickState: 1)
            held.append(button)
        case .mouseUp(let buttonNumber):
            let button = MouseButton(buttonNumber: buttonNumber)
            poster.mouseUp(button, at: poster.currentLocation, clickState: 1)
            if let i = held.firstIndex(of: button) { held.remove(at: i) }
        case .repeatGroup(let count, let steps):
            for _ in 0..<max(count, 1) {
                guard limitsAllow(), runPass(steps) else { return false }
            }
        case .returnToOrigin:
            poster.moveCursor(to: origin)
        }
        return true
    }
}
