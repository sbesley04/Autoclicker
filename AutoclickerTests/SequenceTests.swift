import Foundation
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

@Suite("Sequence validation")
struct SequenceTests {
    private func steps(_ actions: [SequenceAction]) -> [SequenceStep] {
        actions.map { SequenceStep(action: $0) }
    }

    @Test("Empty sequences are invalid")
    func empty() {
        #expect(SequenceValidator.hasErrors([]))
    }

    @Test("A straightforward sequence validates cleanly")
    func valid() {
        let sequence = steps([
            .leftClick, .wait(ms: 100), .doubleClick,
            .randomDelay(minMS: 10, maxMS: 50),
            .moveCursor(x: 10, y: 10), .returnToOrigin,
        ])
        #expect(SequenceValidator.validate(sequence).isEmpty)
    }

    @Test("Negative wait durations are errors")
    func negativeWait() {
        #expect(SequenceValidator.hasErrors(steps([.wait(ms: -1)])))
    }

    @Test("Random delay with min above max is an error")
    func invertedRandomDelay() {
        #expect(SequenceValidator.hasErrors(steps([.randomDelay(minMS: 100, maxMS: 10)])))
        #expect(!SequenceValidator.hasErrors(steps([.randomDelay(minMS: 10, maxMS: 10)])))
    }

    @Test("Unbalanced mouse down/up produces a warning, not an error")
    func unbalancedPress() {
        let issues = SequenceValidator.validate(steps([.mouseDown(button: 0)]))
        #expect(issues.contains { $0.severity == .warning })
        #expect(!issues.contains { $0.severity == .error })
    }

    @Test("Repeat groups: zero count and over-deep nesting are errors")
    func repeatGroupRules() {
        #expect(SequenceValidator.hasErrors(steps([
            .repeatGroup(count: 0, steps: steps([.leftClick])),
        ])))
        // Nesting three levels deep exceeds maxNestingDepth (3 means the
        // third nested group is rejected).
        let deep: [SequenceStep] = steps([
            .repeatGroup(count: 2, steps: steps([
                .repeatGroup(count: 2, steps: steps([
                    .repeatGroup(count: 2, steps: steps([.leftClick])),
                ])),
            ])),
        ])
        #expect(SequenceValidator.hasErrors(deep))
        // Two levels are fine.
        let ok: [SequenceStep] = steps([
            .repeatGroup(count: 2, steps: steps([
                .repeatGroup(count: 2, steps: steps([.leftClick])),
            ])),
        ])
        #expect(!SequenceValidator.hasErrors(ok))
    }

    @Test("Expanded action counting multiplies repeat groups")
    func expandedCount() {
        let sequence = steps([
            .leftClick,
            .repeatGroup(count: 10, steps: steps([.leftClick, .rightClick])),
        ])
        #expect(SequenceValidator.expandedActionCount(sequence) == 21)
    }

    @Test("Sequences that expand beyond the cap are rejected")
    func expansionCap() {
        let bomb = steps([
            .repeatGroup(count: 10_000, steps: steps([
                .repeatGroup(count: 10_000, steps: steps([.leftClick])),
            ])),
        ])
        #expect(SequenceValidator.hasErrors(bomb))
    }

    @Test("Sequence steps survive JSON round-trips inside repeat groups")
    func nestedCodable() throws {
        let sequence = steps([
            .repeatGroup(count: 3, steps: steps([
                .wait(ms: 50),
                .repeatGroup(count: 2, steps: steps([.doubleClick])),
            ])),
        ])
        let data = try JSONEncoder().encode(sequence)
        let decoded = try JSONDecoder().decode([SequenceStep].self, from: data)
        #expect(decoded == sequence)
    }
}
