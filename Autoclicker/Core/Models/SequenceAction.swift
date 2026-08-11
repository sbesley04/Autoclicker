import Foundation
import CoreGraphics

/// One action inside a repeatable sequence.
indirect enum SequenceAction: Equatable {
    case leftClick
    case rightClick
    case middleClick
    case doubleClick
    case wait(ms: Double)
    case randomDelay(minMS: Double, maxMS: Double)
    case moveCursor(x: Double, y: Double)
    case mouseDown(button: Int)
    case mouseUp(button: Int)
    case repeatGroup(count: Int, steps: [SequenceStep])
    case returnToOrigin

    var displayName: String {
        switch self {
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .wait(let ms): return "Wait \(Self.formatMS(ms))"
        case .randomDelay(let a, let b): return "Random Delay \(Self.formatMS(a))–\(Self.formatMS(b))"
        case .moveCursor(let x, let y): return "Move to (\(Int(x)), \(Int(y)))"
        case .mouseDown(let b): return "\(MouseButton(buttonNumber: b).displayName) Down"
        case .mouseUp(let b): return "\(MouseButton(buttonNumber: b).displayName) Up"
        case .repeatGroup(let count, let steps): return "Repeat ×\(count) (\(steps.count) actions)"
        case .returnToOrigin: return "Return to Origin"
        }
    }

    var systemImage: String {
        switch self {
        case .leftClick: return "cursorarrow.click"
        case .rightClick: return "cursorarrow.click.2"
        case .middleClick: return "cursorarrow.click.badge.clock"
        case .doubleClick: return "cursorarrow.rays"
        case .wait: return "clock"
        case .randomDelay: return "dice"
        case .moveCursor: return "arrow.up.and.down.and.arrow.left.and.right"
        case .mouseDown: return "arrow.down.circle"
        case .mouseUp: return "arrow.up.circle"
        case .repeatGroup: return "arrow.triangle.2.circlepath"
        case .returnToOrigin: return "arrow.uturn.backward.circle"
        }
    }

    static func formatMS(_ ms: Double) -> String {
        ms >= 1000 ? String(format: "%.2gs", ms / 1000) : "\(Int(ms))ms"
    }
}

/// A sequence action with a stable identity, for the editor and Codable form.
struct SequenceStep: Equatable, Identifiable {
    var id: UUID = UUID()
    var action: SequenceAction
}

// MARK: - Codable

extension SequenceStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, type, ms, minMS, maxMS, x, y, button, count, steps
    }

    private enum Kind: String, Codable {
        case leftClick, rightClick, middleClick, doubleClick, wait, randomDelay
        case moveCursor, mouseDown, mouseUp, repeatGroup, returnToOrigin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .leftClick: action = .leftClick
        case .rightClick: action = .rightClick
        case .middleClick: action = .middleClick
        case .doubleClick: action = .doubleClick
        case .wait:
            action = .wait(ms: try c.decode(Double.self, forKey: .ms))
        case .randomDelay:
            action = .randomDelay(
                minMS: try c.decode(Double.self, forKey: .minMS),
                maxMS: try c.decode(Double.self, forKey: .maxMS))
        case .moveCursor:
            action = .moveCursor(
                x: try c.decode(Double.self, forKey: .x),
                y: try c.decode(Double.self, forKey: .y))
        case .mouseDown:
            action = .mouseDown(button: try c.decode(Int.self, forKey: .button))
        case .mouseUp:
            action = .mouseUp(button: try c.decode(Int.self, forKey: .button))
        case .repeatGroup:
            action = .repeatGroup(
                count: try c.decode(Int.self, forKey: .count),
                steps: try c.decode([SequenceStep].self, forKey: .steps))
        case .returnToOrigin: action = .returnToOrigin
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch action {
        case .leftClick: try c.encode(Kind.leftClick, forKey: .type)
        case .rightClick: try c.encode(Kind.rightClick, forKey: .type)
        case .middleClick: try c.encode(Kind.middleClick, forKey: .type)
        case .doubleClick: try c.encode(Kind.doubleClick, forKey: .type)
        case .wait(let ms):
            try c.encode(Kind.wait, forKey: .type)
            try c.encode(ms, forKey: .ms)
        case .randomDelay(let minMS, let maxMS):
            try c.encode(Kind.randomDelay, forKey: .type)
            try c.encode(minMS, forKey: .minMS)
            try c.encode(maxMS, forKey: .maxMS)
        case .moveCursor(let x, let y):
            try c.encode(Kind.moveCursor, forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case .mouseDown(let button):
            try c.encode(Kind.mouseDown, forKey: .type)
            try c.encode(button, forKey: .button)
        case .mouseUp(let button):
            try c.encode(Kind.mouseUp, forKey: .type)
            try c.encode(button, forKey: .button)
        case .repeatGroup(let count, let steps):
            try c.encode(Kind.repeatGroup, forKey: .type)
            try c.encode(count, forKey: .count)
            try c.encode(steps, forKey: .steps)
        case .returnToOrigin: try c.encode(Kind.returnToOrigin, forKey: .type)
        }
    }
}

// MARK: - Validation

struct SequenceIssue: Equatable, Identifiable {
    enum Severity: Equatable { case error, warning }
    var id: UUID = UUID()
    var severity: Severity
    var message: String

    static func == (lhs: SequenceIssue, rhs: SequenceIssue) -> Bool {
        lhs.severity == rhs.severity && lhs.message == rhs.message
    }
}

enum SequenceValidator {
    static let maxNestingDepth = 3
    static let maxTotalExpandedActions = 500_000
    static let maxRepeatCount = 10_000
    static let maxWaitMS: Double = 3_600_000

    static func validate(_ steps: [SequenceStep]) -> [SequenceIssue] {
        var issues: [SequenceIssue] = []
        if steps.isEmpty {
            issues.append(SequenceIssue(severity: .error, message: "Sequence is empty — add at least one action."))
            return issues
        }
        var pressedButtons = Set<Int>()
        validate(steps, depth: 1, issues: &issues, pressed: &pressedButtons)
        if !pressedButtons.isEmpty {
            let names = pressedButtons.sorted().map { MouseButton(buttonNumber: $0).displayName }
            issues.append(SequenceIssue(
                severity: .warning,
                message: "\(names.joined(separator: ", ")) pressed but never released. The engine releases held buttons on stop."))
        }
        let total = expandedActionCount(steps)
        if total > maxTotalExpandedActions {
            issues.append(SequenceIssue(
                severity: .error,
                message: "Sequence expands to \(total) actions, exceeding the limit of \(maxTotalExpandedActions)."))
        }
        return issues
    }

    static func hasErrors(_ steps: [SequenceStep]) -> Bool {
        validate(steps).contains { $0.severity == .error }
    }

    private static func validate(
        _ steps: [SequenceStep], depth: Int,
        issues: inout [SequenceIssue], pressed: inout Set<Int>
    ) {
        for step in steps {
            switch step.action {
            case .wait(let ms):
                if ms < 0 { issues.append(SequenceIssue(severity: .error, message: "Wait duration cannot be negative.")) }
                if ms > maxWaitMS { issues.append(SequenceIssue(severity: .error, message: "Wait duration exceeds 1 hour.")) }
            case .randomDelay(let minMS, let maxMS):
                if minMS < 0 { issues.append(SequenceIssue(severity: .error, message: "Random delay minimum cannot be negative.")) }
                if minMS > maxMS { issues.append(SequenceIssue(severity: .error, message: "Random delay minimum is greater than its maximum.")) }
                if maxMS > maxWaitMS { issues.append(SequenceIssue(severity: .error, message: "Random delay maximum exceeds 1 hour.")) }
            case .moveCursor(let x, let y):
                if !x.isFinite || !y.isFinite {
                    issues.append(SequenceIssue(severity: .error, message: "Move-cursor coordinates must be finite numbers."))
                }
            case .mouseDown(let b):
                if pressed.contains(b) {
                    issues.append(SequenceIssue(severity: .warning, message: "\(MouseButton(buttonNumber: b).displayName) pressed twice without a release."))
                }
                pressed.insert(b)
            case .mouseUp(let b):
                if !pressed.contains(b) {
                    issues.append(SequenceIssue(severity: .warning, message: "\(MouseButton(buttonNumber: b).displayName) released without a preceding press."))
                }
                pressed.remove(b)
            case .repeatGroup(let count, let steps):
                if count < 1 { issues.append(SequenceIssue(severity: .error, message: "Repeat count must be at least 1.")) }
                if count > maxRepeatCount { issues.append(SequenceIssue(severity: .error, message: "Repeat count exceeds \(maxRepeatCount).")) }
                if depth >= maxNestingDepth {
                    issues.append(SequenceIssue(severity: .error, message: "Repeat groups may only be nested \(maxNestingDepth) levels deep."))
                } else {
                    if steps.isEmpty {
                        issues.append(SequenceIssue(severity: .error, message: "A repeat group has no actions."))
                    }
                    validate(steps, depth: depth + 1, issues: &issues, pressed: &pressed)
                }
            default:
                break
            }
        }
    }

    static func expandedActionCount(_ steps: [SequenceStep]) -> Int {
        var total = 0
        for step in steps {
            if case .repeatGroup(let count, let inner) = step.action {
                let innerCount = expandedActionCount(inner)
                // Saturating multiply-add to avoid overflow on absurd inputs.
                let (product, overflow1) = innerCount.multipliedReportingOverflow(by: max(count, 1))
                if overflow1 { return Int.max }
                let (sum, overflow2) = total.addingReportingOverflow(product)
                if overflow2 { return Int.max }
                total = sum
            } else {
                total += 1
            }
            if total > maxTotalExpandedActions { return total }
        }
        return total
    }
}
