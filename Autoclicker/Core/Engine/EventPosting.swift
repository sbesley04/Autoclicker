import Foundation
import CoreGraphics

/// Abstraction over mouse-event generation so the engines can be tested with
/// a mock and the Humanization preview can run with a null poster.
protocol EventPosting: AnyObject {
    /// Current pointer location in CG global coordinates.
    var currentLocation: CGPoint { get }

    func moveCursor(to point: CGPoint)
    func mouseDown(_ button: MouseButton, at point: CGPoint, clickState: Int)
    func mouseUp(_ button: MouseButton, at point: CGPoint, clickState: Int)
}

extension EventPosting {
    /// A full press-release click. `clickCount` 2 marks the events as part of
    /// a double click so apps interpret them correctly.
    func click(_ button: MouseButton, at point: CGPoint, clickCount: Int = 1) {
        for state in 1...max(clickCount, 1) {
            mouseDown(button, at: point, clickState: state)
            mouseUp(button, at: point, clickState: state)
        }
    }
}

/// Poster that records events instead of generating them. Used by unit tests
/// and by preview paths that must never emit real input.
final class RecordingEventPoster: EventPosting {
    enum Event: Equatable {
        case move(CGPoint)
        case down(MouseButton, CGPoint, Int)
        case up(MouseButton, CGPoint, Int)
    }

    private let lock = NSLock()
    private var _events: [Event] = []
    var simulatedLocation = CGPoint(x: 100, y: 100)

    var events: [Event] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    var clickCount: Int {
        events.filter { if case .down = $0 { return true } else { return false } }.count
    }

    var currentLocation: CGPoint {
        lock.lock(); defer { lock.unlock() }
        return simulatedLocation
    }

    func moveCursor(to point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        simulatedLocation = point
        _events.append(.move(point))
    }

    func mouseDown(_ button: MouseButton, at point: CGPoint, clickState: Int) {
        lock.lock(); defer { lock.unlock() }
        _events.append(.down(button, point, clickState))
    }

    func mouseUp(_ button: MouseButton, at point: CGPoint, clickState: Int) {
        lock.lock(); defer { lock.unlock() }
        _events.append(.up(button, point, clickState))
    }
}
