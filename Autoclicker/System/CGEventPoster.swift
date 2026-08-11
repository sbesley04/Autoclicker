import Foundation
import CoreGraphics
import AppKit

/// Posts real mouse events through CGEvent.
///
/// Every generated event is tagged in its `eventSourceUserData` field with a
/// magic value so `GlobalInputMonitor`'s event tap can recognize the app's
/// own synthetic events and never treat them as trigger input — this is what
/// prevents self-triggering feedback loops.
final class CGEventPoster: EventPosting {
    /// Arbitrary but distinctive tag ("ACLK" as ASCII, doubled).
    static let syntheticEventTag: Int64 = 0x41434C4B41434C4B

    private let source: CGEventSource?

    init() {
        // .privateState keeps our synthetic-event stream's state (e.g. click
        // counts) isolated from the real input stream.
        source = CGEventSource(stateID: .privateState)
        // Don't let the OS suppress local hardware events around our
        // synthetic ones — the user must always stay in control of the real
        // mouse, especially to reach the stop button.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
    }

    /// Pointer location in CG global coordinates (top-left origin).
    var currentLocation: CGPoint {
        // CGEvent(source:) captures the current hardware cursor location in
        // CG coordinates directly, avoiding manual Cocoa-coordinate flips.
        CGEvent(source: nil)?.location ?? .zero
    }

    func moveCursor(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left) else { return }
        tag(event)
        event.post(tap: .cghidEventTap)
    }

    func mouseDown(_ button: MouseButton, at point: CGPoint, clickState: Int) {
        post(type: button.downEventType, button: button, at: point, clickState: clickState)
    }

    func mouseUp(_ button: MouseButton, at point: CGPoint, clickState: Int) {
        post(type: button.upEventType, button: button, at: point, clickState: clickState)
    }

    private func post(type: CGEventType, button: MouseButton, at point: CGPoint, clickState: Int) {
        guard let event = CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: point, mouseButton: button.cgButton) else { return }
        // clickState 2 marks the second press of a double click so target
        // apps recognize it as such.
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        if case .other(let n) = button {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(n))
        }
        tag(event)
        event.post(tap: .cghidEventTap)
    }

    private func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
    }
}

/// Coordinate-space helpers. CGEvent works in "CG global" coordinates whose
/// origin is the TOP-left of the main display, while AppKit (NSEvent,
/// NSScreen) uses a BOTTOM-left origin. Retina scale factors do not affect
/// either space (both are in points), so conversion is a simple Y flip
/// against the main screen height — valid across multi-monitor layouts
/// because both spaces share the same global frame.
enum ScreenCoordinates {
    /// AppKit (bottom-left) point → CG (top-left) point.
    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        guard let mainScreen = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: mainScreen.frame.maxY - point.y)
    }

    /// CG (top-left) point → AppKit (bottom-left) point.
    static func appKitPoint(fromCG point: CGPoint) -> CGPoint {
        guard let mainScreen = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: mainScreen.frame.maxY - point.y)
    }

    /// The display containing a CG-space point, if any.
    static func screen(containingCG point: CGPoint) -> NSScreen? {
        let appKit = appKitPoint(fromCG: point)
        return NSScreen.screens.first { $0.frame.contains(appKit) }
    }

    /// Current mouse location in CG coordinates without needing any
    /// permission (NSEvent.mouseLocation is always available in-process).
    static func currentMouseLocationCG() -> CGPoint {
        cgPoint(fromAppKit: NSEvent.mouseLocation)
    }
}
