import Foundation
import CoreGraphics
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

@Suite("Click engine", .serialized)
struct EngineTests {
    private func makeEngine() -> (ClickEngine, RecordingEventPoster) {
        let poster = RecordingEventPoster()
        return (ClickEngine(poster: poster), poster)
    }

    @Test("Burst performs the exact configured number of clicks")
    func burstExactCount() {
        let (engine, poster) = makeEngine()
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.002))
        session.maxClicks = 17
        let result = runEngineSession(engine, session)
        #expect(result?.reason == .maxClicksReached)
        #expect(result?.clicks == 17)
        #expect(poster.clickCount == 17)
        #expect(!engine.isRunning)
    }

    @Test("Normal clicks post balanced, alternating down/up pairs")
    func clickDownUpBalance() {
        let (engine, poster) = makeEngine()
        // 50ms interval → the ~18ms game-friendly press applies in full.
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.05))
        session.maxClicks = 6
        let result = runEngineSession(engine, session)
        #expect(result?.clicks == 6)
        let downs = poster.events.filter { if case .down = $0 { return true }; return false }.count
        let ups = poster.events.filter { if case .up = $0 { return true }; return false }.count
        #expect(downs == 6 && ups == 6)
        // Must strictly alternate down,up,… so the button is really released.
        var expectingDown = true
        for event in poster.events {
            switch event {
            case .down: #expect(expectingDown); expectingDown = false
            case .up: #expect(!expectingDown); expectingDown = true
            case .move: break
            }
        }
    }

    @Test("Mouse-down-only never leaves the button stuck down after a session")
    func mouseDownOnlyReleasesOnStop() {
        let (engine, poster) = makeEngine()
        var session = ClickSession(
            payload: .click(type: .mouseDownOnly, holdDurationMS: 0),
            timing: .fixed(seconds: 0.005))
        session.maxClicks = 4
        let result = runEngineSession(engine, session)
        #expect(result?.clicks == 4)
        // Whatever it pressed, cleanup must leave nothing held: the number of
        // ups must match the number of downs, otherwise the user's mouse is
        // left in a dragging state system-wide.
        let downs = poster.events.filter { if case .down = $0 { return true }; return false }.count
        let ups = poster.events.filter { if case .up = $0 { return true }; return false }.count
        #expect(ups >= 1, "cleanup must release the held button")
        #expect(downs == ups, "every press must be balanced by a release")
    }

    @Test("Humanized burst still performs the exact click count")
    func humanizedBurstCount() {
        let (engine, poster) = makeEngine()
        var timing = HumanizedTiming()
        timing.targetCPS = 200
        timing.minIntervalMS = 1
        timing.maxIntervalMS = 20
        timing.seed = 5
        timing.burstProbability = 0.2
        timing.hesitationProbability = 0.1
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .humanized(timing))
        session.maxClicks = 25
        let result = runEngineSession(engine, session)
        #expect(result?.clicks == 25)
        #expect(poster.clickCount == 25)
    }

    @Test("Maximum click count is enforced over a smaller burst setting")
    func maxClickComposition() {
        var profile = Profile()
        profile.mode = .burst
        profile.speed.burstCount = 50
        profile.safety.maxClicks = 8
        let session = AppState.buildSession(for: profile)
        #expect(session.maxClicks == 8)
    }

    @Test("Maximum runtime stops the session")
    func maxRuntime() {
        let (engine, _) = makeEngine()
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.01))
        session.maxRuntime = 0.2
        let clock = Date()
        let result = runEngineSession(engine, session)
        #expect(result?.reason == .maxRuntimeReached)
        #expect(Date().timeIntervalSince(clock) < 3)
    }

    @Test("Stop interrupts a long randomized delay immediately")
    func immediateStopDuringDelay() {
        let (engine, _) = makeEngine()
        var timing = HumanizedTiming()
        timing.targetCPS = 0.2 // 5-second mean interval
        timing.minIntervalMS = 4000
        timing.maxIntervalMS = 8000
        let session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .humanized(timing))
        var stopIssued: Date?
        let result = runEngineSession(
            engine, session,
            onClick: { _, _ in
                // First click reported → engine is inside its long wait next.
                if stopIssued == nil {
                    stopIssued = Date()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                        engine.stop(reason: .emergencyStop)
                    }
                }
            })
        #expect(result?.reason == .emergencyStop)
        if let stopIssued {
            // Far less than the 4–8 s interval: the wait was interrupted.
            #expect(Date().timeIntervalSince(stopIssued) < 1.5)
        } else {
            Issue.record("never clicked")
        }
    }

    @Test("Click-and-hold releases the button when stopped mid-hold")
    func holdReleaseOnStop() {
        let (engine, poster) = makeEngine()
        let session = ClickSession(
            payload: .click(type: .clickAndHold, holdDurationMS: 60_000),
            timing: .fixed(seconds: 0.01))
        let started = DispatchSemaphore(value: 0)
        let clock = Date()
        let result = runEngineSession(
            engine, session,
            afterStart: {
                started.signal()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    engine.stop(reason: .userRequested)
                }
            })
        #expect(result != nil)
        #expect(Date().timeIntervalSince(clock) < 5)
        // The mouse-down must be balanced by a mouse-up despite the
        // interrupted 60 s hold.
        let downs = poster.events.filter { if case .down = $0 { return true } else { return false } }.count
        let ups = poster.events.filter { if case .up = $0 { return true } else { return false } }.count
        #expect(downs == ups)
        #expect(downs >= 1)
    }

    @Test("Two sessions can never run simultaneously")
    func noConcurrentSessions() {
        let (engine, _) = makeEngine()
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.01))
        session.maxRuntime = 1.0
        let done = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let ok = engine.start(session, callbacks: ClickEngineCallbacks(
            onStart: { started.signal() },
            onStop: { _, _ in done.signal() }))
        #expect(ok)
        _ = started.wait(timeout: .now() + 5)
        // Second start while running must be refused.
        #expect(engine.start(session, callbacks: ClickEngineCallbacks()) == false)
        engine.stop()
        #expect(done.wait(timeout: .now() + 5) == .success)
    }

    @Test("Countdown delays clicking and is interruptible")
    func countdown() {
        let (engine, poster) = makeEngine()
        var session = ClickSession(
            payload: .click(type: .left, holdDurationMS: 0),
            timing: .fixed(seconds: 0.01))
        session.countdownSeconds = 30
        var ticks: [Int] = []
        let done = DispatchSemaphore(value: 0)
        _ = engine.start(session, callbacks: ClickEngineCallbacks(
            onCountdownTick: { remaining in
                ticks.append(remaining)
                if ticks.count == 1 {
                    DispatchQueue.global().async { engine.stop(reason: .userRequested) }
                }
            },
            onStop: { _, _ in done.signal() }))
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(poster.clickCount == 0, "no clicks may fire during the countdown")
        #expect(ticks.first == 30)
    }

    @Test("Return-to-origin moves the cursor back after the session")
    func returnToOrigin() {
        let (engine, poster) = makeEngine()
        poster.simulatedLocation = CGPoint(x: 321, y: 123)
        var session = ClickSession(
            payload: .sequence(steps: [
                SequenceStep(action: .moveCursor(x: 50, y: 60)),
                SequenceStep(action: .leftClick),
            ], loop: false),
            timing: .fixed(seconds: 0.01))
        session.targeting.returnToOrigin = true
        let result = runEngineSession(engine, session)
        #expect(result?.reason == .sequenceCompleted)
        if case .move(let point)? = poster.events.last {
            #expect(point == CGPoint(x: 321, y: 123))
        } else {
            Issue.record("expected final cursor restore, got \(String(describing: poster.events.last))")
        }
    }

    @Test("Sequence executes actions in order")
    func sequenceOrder() {
        let (engine, poster) = makeEngine()
        let steps = [
            SequenceStep(action: .leftClick),
            SequenceStep(action: .wait(ms: 5)),
            SequenceStep(action: .rightClick),
            SequenceStep(action: .doubleClick),
        ]
        let session = ClickSession(
            payload: .sequence(steps: steps, loop: false),
            timing: .fixed(seconds: 0.005))
        let result = runEngineSession(engine, session)
        #expect(result?.reason == .sequenceCompleted)
        let downs: [MouseButton] = poster.events.compactMap {
            if case .down(let button, _, _) = $0 { return button } else { return nil }
        }
        #expect(downs == [.left, .right, .left, .left])
    }

    @Test("Repeat group multiplies clicks and honors limits")
    func repeatGroup() {
        let (engine, poster) = makeEngine()
        let steps = [
            SequenceStep(action: .repeatGroup(count: 4, steps: [
                SequenceStep(action: .leftClick),
            ])),
        ]
        let session = ClickSession(
            payload: .sequence(steps: steps, loop: false),
            timing: .fixed(seconds: 0.001))
        let result = runEngineSession(engine, session)
        #expect(result?.clicks == 4)
        #expect(poster.clickCount == 4)
    }

    @Test("Looping sequence stops on request")
    func loopingSequenceStops() {
        let (engine, poster) = makeEngine()
        let steps = [SequenceStep(action: .leftClick), SequenceStep(action: .wait(ms: 5))]
        let session = ClickSession(
            payload: .sequence(steps: steps, loop: true),
            timing: .fixed(seconds: 0.005))
        let result = runEngineSession(
            engine, session,
            onClick: { count, _ in
                if count == 5 { DispatchQueue.global().async { engine.stop() } }
            })
        #expect(result?.reason == .userRequested)
        #expect(poster.clickCount >= 5)
    }
}
