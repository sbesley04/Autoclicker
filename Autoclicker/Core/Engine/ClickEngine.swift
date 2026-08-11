import Foundation
import CoreGraphics

/// Everything the engine needs to run one clicking session. Built by
/// AppState from the active profile so the worker thread never touches
/// mutable shared state.
struct ClickSession {
    enum Payload {
        case click(type: ClickType, holdDurationMS: Double)
        case sequence(steps: [SequenceStep], loop: Bool)
    }

    var payload: Payload
    var timing: EffectiveTiming
    var targeting: TargetingConfig = TargetingConfig()
    /// Cursor jitter radius in points (0 = off).
    var jitterRadius: Double = 0
    /// Hard cap on click cycles (burst count and/or safety limit).
    var maxClicks: Int? = nil
    /// Hard cap on session runtime in seconds.
    var maxRuntime: TimeInterval? = nil
    var countdownSeconds: Double = 0
    /// Seed for targeting/jitter randomness (nil = system entropy).
    var seed: UInt64? = nil
}

/// Callbacks fire on the engine's worker thread — the receiver is
/// responsible for hopping to the main actor.
struct ClickEngineCallbacks {
    var onCountdownTick: (Int) -> Void = { _ in }
    var onStart: () -> Void = {}
    /// (session click count so far, interval before the next click).
    var onClick: (Int, TimeInterval) -> Void = { _, _ in }
    var onStop: (StopReason, Int) -> Void = { _, _ in }
}

/// Executes clicking sessions on a dedicated worker thread. The main thread
/// is never blocked; stop requests interrupt any wait immediately via
/// `InterruptibleWaiter`. Only one session can run at a time.
final class ClickEngine {
    /// Default button-down hold for instantaneous clicks. Long enough that a
    /// game polling button state at ~60Hz (and usually much slower per game
    /// tick) reliably sees the press, short enough to be invisible at normal
    /// rates. Automatically shortened when the click interval is smaller.
    static let gameFriendlyPressSeconds: TimeInterval = 0.018

    private let poster: EventPosting
    private let stateLock = NSLock()
    private var running = false
    private var waiter: InterruptibleWaiter?
    private var requestedStopReason: StopReason?

    init(poster: EventPosting) {
        self.poster = poster
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    /// Starts a session. Returns false (and does nothing) if one is already
    /// running — this is the "no two simultaneous sessions" guarantee.
    @discardableResult
    func start(_ session: ClickSession, callbacks: ClickEngineCallbacks) -> Bool {
        stateLock.lock()
        guard !running else {
            stateLock.unlock()
            return false
        }
        running = true
        requestedStopReason = nil
        let sessionWaiter = InterruptibleWaiter()
        waiter = sessionWaiter
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.run(session, waiter: sessionWaiter, callbacks: callbacks)
        }
        thread.name = "com.autoclicker.click-engine"
        // High QoS keeps click timing accurate under load without needing a
        // real-time thread.
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// Requests an immediate stop. Safe to call from any thread, repeatedly.
    /// The first reason supplied wins (so emergency-stop can't be
    /// overwritten by a later, softer reason).
    func stop(reason: StopReason = .userRequested) {
        stateLock.lock()
        guard running else {
            stateLock.unlock()
            return
        }
        if requestedStopReason == nil { requestedStopReason = reason }
        let sessionWaiter = waiter
        stateLock.unlock()
        sessionWaiter?.cancel()
    }

    // MARK: - Worker

    private func run(_ session: ClickSession, waiter: InterruptibleWaiter, callbacks: ClickEngineCallbacks) {
        let rng = RandomSource(seed: session.seed)
        let resolver = TargetResolver(
            config: session.targeting, jitterRadius: session.jitterRadius,
            rng: rng, poster: poster)
        let generator = IntervalGeneratorFactory.make(for: session.timing)
        var clickCount = 0
        var naturalReason: StopReason?
        /// Buttons currently held down by this session (click-and-hold or an
        /// unbalanced sequence). Always released in cleanup so the system is
        /// never left with a stuck button.
        var heldButtons: [MouseButton] = []

        // Startup countdown, one tick per second, fully interruptible.
        if session.countdownSeconds > 0 {
            var remaining = session.countdownSeconds
            while remaining > 0 && !waiter.isCancelled {
                callbacks.onCountdownTick(Int(remaining.rounded(.up)))
                if !waiter.wait(min(1, remaining)) { break }
                remaining -= 1
            }
        }

        let origin = poster.currentLocation
        let deadline: Date? = session.maxRuntime.map { Date().addingTimeInterval($0) }
        callbacks.onStart()

        func limitsAllowAnotherCycle() -> Bool {
            if let max = session.maxClicks, clickCount >= max {
                naturalReason = .maxClicksReached
                return false
            }
            if let deadline, Date() >= deadline {
                naturalReason = .maxRuntimeReached
                return false
            }
            return true
        }

        /// Interruptible wait that also respects the runtime deadline.
        func pause(_ seconds: TimeInterval) -> Bool {
            var toWait = seconds
            if let deadline {
                toWait = min(toWait, max(0, deadline.timeIntervalSinceNow))
            }
            guard waiter.wait(toWait) else { return false }
            if let deadline, Date() >= deadline {
                naturalReason = .maxRuntimeReached
                return false
            }
            return true
        }

        // Performs one click and returns the time (seconds) it spent holding
        // the button down — the caller subtracts this from the following
        // interval so the requested click rate is preserved. Returns nil if
        // the session was interrupted mid-click. A small press-hold is
        // applied to instantaneous clicks so games that poll button *state*
        // each frame (e.g. per game-tick) actually observe the press; the
        // hold is bounded by the interval so it never slows high rates.
        func performClickCycle(_ type: ClickType, holdDurationMS: Double, interval: TimeInterval) -> TimeInterval? {
            let point = resolver.nextPoint()
            switch type {
            case .left, .right, .middle:
                let press = min(Self.gameFriendlyPressSeconds, interval * 0.5)
                poster.mouseDown(type.button, at: point, clickState: 1)
                if press > 0 {
                    heldButtons.append(type.button)
                    let finished = pause(press)
                    poster.mouseUp(type.button, at: point, clickState: 1)
                    heldButtons.removeAll { $0 == type.button }
                    // The click completed (both down and up were posted), so
                    // count it even if the session was interrupted mid-press.
                    clickCount += 1
                    if !finished { return nil }
                    return press
                }
                poster.mouseUp(type.button, at: point, clickState: 1)
                clickCount += 1
                return press
            case .double:
                let press = min(Self.gameFriendlyPressSeconds, interval * 0.25)
                for state in 1...2 {
                    poster.mouseDown(.left, at: point, clickState: state)
                    if press > 0 {
                        heldButtons.append(.left)
                        let finished = pause(press)
                        poster.mouseUp(.left, at: point, clickState: state)
                        heldButtons.removeAll { $0 == .left }
                        if !finished { return nil }
                    } else {
                        poster.mouseUp(.left, at: point, clickState: state)
                    }
                }
                clickCount += 1
                return press * 2
            case .mouseDownOnly:
                // Mouse button state is binary, so pressing an already-held
                // button is a no-op — re-posting would just flood the target
                // app with bogus press events. Track the press so cleanup
                // releases it when the session ends; without that the button
                // stays logically held system-wide and the user is left
                // stuck in a drag. The cycle is still counted so click/time
                // limits continue to terminate the session.
                if !heldButtons.contains(.left) {
                    poster.mouseDown(.left, at: point, clickState: 1)
                    heldButtons.append(.left)
                }
                clickCount += 1
                return 0
            case .mouseUpOnly:
                // Likewise, only release a button that is actually held.
                if heldButtons.contains(.left) {
                    poster.mouseUp(.left, at: point, clickState: 1)
                    heldButtons.removeAll { $0 == .left }
                } else {
                    // Nothing held by this session — still emit one release
                    // so the mode can clear a button held by something else.
                    poster.mouseUp(.left, at: point, clickState: 1)
                }
                clickCount += 1
                return 0
            case .clickAndHold:
                poster.mouseDown(.left, at: point, clickState: 1)
                heldButtons.append(.left)
                let finished = pause(holdDurationMS / 1000)
                poster.mouseUp(.left, at: point, clickState: 1)
                heldButtons.removeAll { $0 == .left }
                // Both down and up were posted, so the click completed even
                // if the hold was cut short by a stop.
                clickCount += 1
                if !finished { return nil }
                // Don't subtract from the interval — click-and-hold's timing
                // is (hold + interval) by design.
                return 0
            }
        }

        switch session.payload {
        case .click(let type, let holdDurationMS):
            while !waiter.isCancelled && limitsAllowAnotherCycle() {
                let interval = generator.next()
                guard let consumed = performClickCycle(type, holdDurationMS: holdDurationMS, interval: interval) else { break }
                guard limitsAllowAnotherCycle() else { break }
                callbacks.onClick(clickCount, interval)
                guard pause(max(0, interval - consumed)) else { break }
            }

        case .sequence(let steps, let loop):
            let runner = SequenceRunner(
                poster: poster, rng: rng, origin: origin,
                pause: pause,
                interActionInterval: {
                    if case .humanized = session.timing { return generator.next() }
                    return SequenceRunner.defaultGapSeconds
                },
                onClick: { interval in
                    clickCount += 1
                    callbacks.onClick(clickCount, interval)
                },
                limitsAllow: limitsAllowAnotherCycle,
                heldButtons: { heldButtons = $0 })
            repeat {
                guard runner.runPass(steps), !waiter.isCancelled else { break }
            } while loop && limitsAllowAnotherCycle()
            if !loop && naturalReason == nil && requestedReason() == nil {
                naturalReason = .sequenceCompleted
            }
        }

        // Cleanup — always runs, regardless of how the loop ended.
        for button in heldButtons {
            poster.mouseUp(button, at: poster.currentLocation, clickState: 1)
        }
        if session.targeting.returnToOrigin {
            poster.moveCursor(to: origin)
        }

        stateLock.lock()
        let reason = requestedStopReason ?? naturalReason ?? .userRequested
        running = false
        self.waiter = nil
        stateLock.unlock()
        callbacks.onStop(reason, clickCount)
    }

    private func requestedReason() -> StopReason? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requestedStopReason
    }
}
