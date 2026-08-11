import Foundation
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

@Suite("Trigger state machine")
struct TriggerModeTests {
    @Test("Toggle mode starts on first press and stops on second")
    func toggleMode() {
        var machine = TriggerStateMachine(mode: .toggle)
        #expect(machine.handle(.triggerPressed) == .startContinuous)
        #expect(machine.isActive)
        #expect(machine.handle(.triggerReleased) == .none)
        #expect(machine.handle(.triggerPressed) == .stop(.userRequested))
        #expect(!machine.isActive)
        #expect(machine.handle(.triggerPressed) == .startContinuous)
    }

    @Test("Hold mode starts on press and stops on release")
    func holdMode() {
        var machine = TriggerStateMachine(mode: .hold)
        #expect(machine.handle(.triggerPressed) == .startContinuous)
        // Duplicate press (e.g. key repeat) must not restart the session.
        #expect(machine.handle(.triggerPressed) == .none)
        #expect(machine.handle(.triggerReleased) == .stop(.triggerReleased))
        #expect(!machine.isActive)
        // Release without press is ignored.
        #expect(machine.handle(.triggerReleased) == .none)
    }

    @Test("Burst mode fires once per press and ignores presses mid-burst")
    func burstMode() {
        var machine = TriggerStateMachine(mode: .burst)
        #expect(machine.handle(.triggerPressed) == .startBurst)
        // Rapid re-press while the burst is still running: ignored.
        #expect(machine.handle(.triggerPressed) == .none)
        #expect(machine.handle(.sessionEnded) == .none)
        #expect(!machine.isActive)
        #expect(machine.handle(.triggerPressed) == .startBurst)
    }

    @Test("One-shot mode performs one action per press")
    func oneShotMode() {
        var machine = TriggerStateMachine(mode: .oneShot)
        #expect(machine.handle(.triggerPressed) == .startOneShot)
        #expect(machine.handle(.triggerPressed) == .none)
        #expect(machine.handle(.sessionEnded) == .none)
        #expect(machine.handle(.triggerPressed) == .startOneShot)
    }

    @Test("Humanized Rapid and Repeat Sequence use toggle semantics")
    func continuousModes() {
        for mode in [ActivationMode.humanizedRapid, .repeatSequence] {
            var machine = TriggerStateMachine(mode: mode)
            #expect(machine.handle(.triggerPressed) == .startContinuous)
            #expect(machine.handle(.triggerPressed) == .stop(.userRequested))
        }
    }

    @Test("Emergency stop wins in every mode and every state")
    func emergencyStopPriority() {
        for mode in ActivationMode.allCases {
            var machine = TriggerStateMachine(mode: mode)
            // Inactive: emergency stop is a no-op command but never throws
            // the machine into an active state.
            #expect(machine.handle(.emergencyStop) == .none)
            #expect(!machine.isActive)
            // Active: emergency stop always yields .stop(.emergencyStop).
            _ = machine.handle(.triggerPressed)
            #expect(machine.handle(.emergencyStop) == .stop(.emergencyStop))
            #expect(!machine.isActive)
            // After an emergency stop the next press works normally again.
            let next = machine.handle(.triggerPressed)
            #expect(next != .none)
        }
    }

    @Test("Rapid trigger mashing never produces overlapping starts")
    func rapidPresses() {
        var machine = TriggerStateMachine(mode: .toggle)
        var startCount = 0
        var stopCount = 0
        for _ in 0..<101 {
            switch machine.handle(.triggerPressed) {
            case .startContinuous: startCount += 1
            case .stop: stopCount += 1
            default: break
            }
        }
        // Strict alternation: starts and stops interleave, never two starts
        // without a stop between them.
        #expect(startCount == 51)
        #expect(stopCount == 50)
    }
}

@Suite("Emergency stop reason precedence")
struct StopReasonPrecedenceTests {
    @Test("The first stop reason wins over later softer reasons")
    func reasonPrecedence() {
        let poster = RecordingEventPoster()
        let engine = ClickEngine(poster: poster)
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.02))
        session.maxClicks = 100_000
        let done = DispatchSemaphore(value: 0)
        var reported: StopReason?
        let started = DispatchSemaphore(value: 0)
        let callbacks = ClickEngineCallbacks(
            onStart: { started.signal() },
            onStop: { reason, _ in reported = reason; done.signal() })
        #expect(engine.start(session, callbacks: callbacks))
        _ = started.wait(timeout: .now() + 5)
        engine.stop(reason: .emergencyStop)
        engine.stop(reason: .userRequested) // must NOT overwrite
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(reported == .emergencyStop)
    }
}
