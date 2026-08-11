import Foundation
import SwiftUI
import Combine
import AppKit

/// Central coordinator. Owns every subsystem and is the only place that
/// translates trigger/monitor events into engine commands. All published
/// state is main-actor; engine callbacks funnel through a lock-protected
/// buffer drained by a UI timer so high click rates never flood the main
/// thread.
final class AppState: ObservableObject {
    // MARK: Subsystems

    let profileStore: ProfileStore
    let settingsStore: SettingsStore
    let permissions: PermissionManager
    let monitor: GlobalInputMonitor
    let engine: ClickEngine
    let sounds = SoundManager()
    private let systemEvents = SystemEventObserver()

    // MARK: Published state

    /// Armed = the global trigger is live. Disarmed = only UI start works.
    @Published var isArmed = false {
        didSet {
            guard isArmed != oldValue else { return }
            syncMonitorConfiguration()
            // Remember across launches so the trigger doesn't silently need
            // re-arming every time the app starts.
            if settingsStore.settings.wasArmed != isArmed {
                settingsStore.settings.wasArmed = isArmed
            }
        }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var countdownRemaining: Int? = nil
    @Published private(set) var sessionClicks = 0
    @Published private(set) var lifetimeClicks = 0
    @Published private(set) var sessionStart: Date? = nil
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var stats = IntervalStatistics()
    @Published private(set) var lastStopReason: StopReason? = nil

    /// Whether the app is frontmost. Ambient UI animations pause when it is
    /// not, so switching to a full-screen game drops the app's CPU use to
    /// near zero without affecting the click engine (which runs off-thread).
    @Published private(set) var isAppActive = true

    /// Diagnostics feed (Trigger screen).
    @Published private(set) var recentInputs: [DetectedInput] = []
    @Published var diagnosticsEnabled = false {
        didSet { syncMonitorConfiguration() }
    }

    /// Input-detection mode state.
    @Published private(set) var isDetectingInput = false
    @Published private(set) var lastDetectedCandidate: DetectedInput? = nil

    /// Coordinate capture state.
    @Published private(set) var isCapturingPoint = false

    /// Set when a start was blocked pending high-rate confirmation.
    @Published var pendingHighRateStart: Bool = false
    private var highRateConfirmed = false

    // MARK: Private

    private var triggerMachine = TriggerStateMachine(mode: .toggle)
    private var cancellables: Set<AnyCancellable> = []
    private var uiTimer: Timer?

    /// Click events buffered off the worker thread.
    private let clickBufferLock = NSLock()
    private var bufferedClicks: [(count: Int, interval: TimeInterval)] = []

    // MARK: Init

    init(profileStore: ProfileStore = ProfileStore(),
         settingsStore: SettingsStore = SettingsStore(),
         permissions: PermissionManager = PermissionManager(),
         poster: EventPosting = CGEventPoster()) {
        self.profileStore = profileStore
        self.settingsStore = settingsStore
        self.permissions = permissions
        self.monitor = GlobalInputMonitor()
        self.engine = ClickEngine(poster: poster)

        sounds.isEnabled = { [weak self] in self?.settingsStore.settings.soundsEnabled ?? false }
        wireMonitor()
        wireSystemEvents()
        wirePermissions()

        // Forward child-store change signals so views observing AppState
        // re-render on profile/settings edits, and keep the monitor
        // configuration in sync (after the change lands, hence async).
        for publisher in [profileStore.objectWillChange.eraseToAnyPublisher(),
                          settingsStore.objectWillChange.eraseToAnyPublisher(),
                          monitor.objectWillChange.eraseToAnyPublisher()] {
            publisher
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    DispatchQueue.main.async { self?.syncMonitorConfiguration() }
                }
                .store(in: &cancellables)
        }

        startUITimer()
        if permissions.coreGranted {
            monitor.start()
        }
        syncMonitorConfiguration()

        // Restore the armed state, but only when it can actually work: a
        // trigger must be assigned and permissions granted. Otherwise the UI
        // would claim "armed" while nothing could fire.
        if settingsStore.settings.rememberArmedState,
           settingsStore.settings.wasArmed,
           permissions.coreGranted,
           profileStore.selectedProfile?.trigger.isAssigned == true {
            isArmed = true
        }

        // Register with the Input Monitoring system so the app shows up in
        // its System Settings list (and prompts once if the status is still
        // undetermined). Deferred so the UI finishes launching first.
        DispatchQueue.main.async { [weak self] in
            self?.permissions.registerForInputMonitoring()
        }
    }

    // MARK: Selected profile access

    var selectedProfile: Profile? { profileStore.selectedProfile }

    /// Mutating access used by every editor screen; persists automatically.
    func updateSelectedProfile(_ mutate: (inout Profile) -> Void) {
        guard var profile = profileStore.selectedProfile else { return }
        mutate(&profile)
        profileStore.update(profile)
        highRateConfirmed = false // settings changed → re-confirm high rates
        syncMonitorConfiguration()
    }

    func selectProfile(_ id: UUID) {
        guard id != profileStore.selectedProfileID else { return }
        stop(reason: .userRequested)
        profileStore.selectedProfileID = id
        highRateConfirmed = false
        sounds.play(.profileSwitch)
        syncMonitorConfiguration()
    }

    // MARK: Wiring

    private func wireMonitor() {
        monitor.onTriggerDown = { [weak self] in self?.handleTrigger(.triggerPressed) }
        monitor.onTriggerUp = { [weak self] in self?.handleTrigger(.triggerReleased) }
        // Kill the engine directly from the tap thread — instant, no main
        // thread dependency. The main-queue handler then updates UI state.
        monitor.onEmergencyStopImmediate = { [weak self] in
            self?.engine.stop(reason: .emergencyStop)
        }
        monitor.onEmergencyStop = { [weak self] in self?.emergencyStop() }
        monitor.onDetectedInput = { [weak self] input in
            guard let self, self.diagnosticsEnabled else { return }
            self.recentInputs.insert(input, at: 0)
            if self.recentInputs.count > 60 { self.recentInputs.removeLast() }
        }
        monitor.onCapturedInput = { [weak self] input in
            // Only the first input is taken; ignore anything that arrives
            // after (the tap is torn down below, but events already in
            // flight can still land here).
            guard let self, self.isDetectingInput,
                  self.lastDetectedCandidate == nil else { return }
            self.lastDetectedCandidate = input
            // Stop capturing now that we have a candidate, so the user's
            // click on "Assign" can't replace it.
            self.syncMonitorConfiguration()
        }
        monitor.onCapturedPoint = { [weak self] point in
            guard let self, self.isCapturingPoint else { return }
            self.finishPointCapture(with: point)
        }
    }

    private func wireSystemEvents() {
        systemEvents.onSleep = { [weak self] in self?.stop(reason: .systemSleep) }
        systemEvents.onWake = { [weak self] in
            // Event taps are frequently disabled or invalidated across
            // sleep/wake. Repair ours so triggers keep working without
            // needing an app restart. Slight delay: the window server isn't
            // immediately ready right at wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.permissions.refresh()
                self?.monitor.verifyAlive()
            }
        }
        systemEvents.onDisplayChange = { [weak self] in
            guard let self, self.isRunning,
                  let profile = self.selectedProfile,
                  profile.targeting.mode.usesSavedPoints else { return }
            // Saved coordinates may no longer exist on screen — fail safe.
            self.stop(reason: .userRequested)
        }
        systemEvents.onActiveAppChange = { [weak self] _ in
            guard let self, self.isRunning,
                  self.selectedProfile?.safety.stopOnAppSwitch == true else { return }
            self.stop(reason: .appSwitched)
        }
        systemEvents.onAppActiveChange = { [weak self] active in
            self?.isAppActive = active
        }
        systemEvents.start()
    }

    private func wirePermissions() {
        permissions.onPermissionsLost = { [weak self] in
            guard let self else { return }
            self.stop(reason: .permissionsLost)
            self.isArmed = false
            self.monitor.stop()
        }
        // Restart the tap once permissions appear.
        permissions.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status.isGranted && !self.monitor.isMonitoring {
                    self.monitor.start()
                }
            }
            .store(in: &cancellables)
    }

    /// Pushes the current trigger/emergency/capture snapshot into the tap.
    private func syncMonitorConfiguration() {
        var config = MonitorConfiguration()
        config.trigger = isArmed ? (selectedProfile?.trigger ?? .none) : .none
        config.behavior = selectedProfile?.inputBehavior ?? .passThrough
        config.emergencyStop = settingsStore.settings.emergencyStop
        config.diagnosticsEnabled = diagnosticsEnabled
        // Stop listening as soon as something has been captured. Otherwise
        // the left-click the user makes to press "Assign" would itself be
        // captured and overwrite their selection — making it impossible to
        // assign anything but the left button.
        if isDetectingInput && lastDetectedCandidate == nil {
            config.captureMode = .detectInput
        } else if isCapturingPoint {
            config.captureMode = .capturePoint
        }
        monitor.configuration = config
    }

    // MARK: Trigger handling

    private func handleTrigger(_ event: TriggerStateMachine.Event) {
        guard isArmed, !isDetectingInput, !isCapturingPoint else { return }
        guard let profile = selectedProfile else { return }
        triggerMachine.setMode(profile.mode)
        execute(triggerMachine.handle(event))
    }

    private func execute(_ command: TriggerStateMachine.Command, confirmHighRate: Bool = false) {
        switch command {
        case .none:
            break
        case .startContinuous, .startBurst, .startOneShot:
            startSession(confirmHighRate: confirmHighRate)
        case .stop(let reason):
            engine.stop(reason: reason)
        }
    }

    // MARK: Start / stop

    /// Start from the dashboard button (bypasses arming, still checks
    /// permissions and confirmation).
    func startFromUI() {
        guard !isRunning else { return }
        guard let profile = selectedProfile else { return }
        triggerMachine.setMode(profile.mode)
        switch profile.mode {
        case .hold:
            // Hold mode has no meaning from a UI button; run as toggle.
            _ = triggerMachine.handle(.triggerPressed)
            startSession(confirmHighRate: true)
        default:
            execute(triggerMachine.handle(.triggerPressed), confirmHighRate: true)
        }
    }

    func toggleFromUI() {
        if isRunning {
            stop(reason: .userRequested)
        } else {
            startFromUI()
        }
    }

    private func startSession(confirmHighRate: Bool) {
        guard let profile = selectedProfile else { return }
        guard permissions.coreGranted else {
            lastStopReason = .permissionsLost
            sounds.play(.error)
            _ = triggerMachine.handle(.sessionEnded)
            return
        }
        if let issue = profile.validationIssues().first {
            lastStopReason = .error(issue)
            sounds.play(.error)
            _ = triggerMachine.handle(.sessionEnded)
            return
        }
        // High-rate confirmation gate — only for UI-initiated starts, where
        // the confirmation dialog is actually visible. A global trigger only
        // fires because the user deliberately armed the profile, and popping
        // an invisible dialog behind a full-screen game would just make the
        // autoclicker silently refuse to start.
        if confirmHighRate,
           profile.safety.confirmHighRates,
           profile.estimatedCPS > SpeedConfig.highRateThresholdCPS,
           !highRateConfirmed {
            pendingHighRateStart = true
            _ = triggerMachine.handle(.sessionEnded)
            return
        }

        let session = Self.buildSession(for: profile)
        let callbacks = ClickEngineCallbacks(
            onCountdownTick: { [weak self] remaining in
                DispatchQueue.main.async {
                    self?.countdownRemaining = remaining
                    self?.sounds.play(.countdownTick)
                }
            },
            onStart: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.countdownRemaining = nil
                    self.sessionStart = Date()
                }
            },
            onClick: { [weak self] count, interval in
                guard let self else { return }
                self.clickBufferLock.lock()
                self.bufferedClicks.append((count, interval))
                self.clickBufferLock.unlock()
            },
            onStop: { [weak self] reason, totalClicks in
                DispatchQueue.main.async {
                    self?.sessionDidStop(reason: reason, clicks: totalClicks)
                }
            })

        guard engine.start(session, callbacks: callbacks) else { return }
        isRunning = true
        lastStopReason = nil
        sessionClicks = 0
        sessionDuration = 0
        sessionStart = nil
        stats.reset()
        countdownRemaining = session.countdownSeconds > 0 ? Int(session.countdownSeconds.rounded(.up)) : nil
        sounds.play(.start)
    }

    /// Called after the user confirms a high-rate start.
    func confirmHighRateAndStart() {
        highRateConfirmed = true
        pendingHighRateStart = false
        startFromUI()
    }

    func stop(reason: StopReason = .userRequested) {
        engine.stop(reason: reason)
    }

    /// Highest-priority stop: kills the session and disarms the trigger.
    func emergencyStop() {
        engine.stop(reason: .emergencyStop)
        _ = triggerMachine.handle(.emergencyStop)
        isArmed = false
        if !isRunning {
            // Even when nothing is running, surface the state change.
            lastStopReason = .emergencyStop
        }
        sounds.play(.stop)
    }

    private func sessionDidStop(reason: StopReason, clicks: Int) {
        isRunning = false
        countdownRemaining = nil
        drainClickBuffer()
        sessionClicks = clicks
        lifetimeClicks += max(0, clicks - statsSessionBase)
        statsSessionBase = 0
        lastStopReason = reason
        _ = triggerMachine.handle(.sessionEnded)
        if reason != .emergencyStop { // emergencyStop() already played a sound
            sounds.play(.stop)
        }
    }

    private var statsSessionBase = 0

    static func buildSession(for profile: Profile) -> ClickSession {
        var session: ClickSession
        let humanized = profile.humanization.enabled

        switch profile.mode {
        case .repeatSequence:
            session = ClickSession(
                payload: .sequence(steps: profile.sequence, loop: true),
                timing: humanized ? .humanized(profile.humanization.timing) : .fixed(seconds: SequenceRunner.defaultGapSeconds))
        case .oneShot where !profile.sequence.isEmpty:
            session = ClickSession(
                payload: .sequence(steps: profile.sequence, loop: false),
                timing: humanized ? .humanized(profile.humanization.timing) : .fixed(seconds: SequenceRunner.defaultGapSeconds))
        case .oneShot:
            session = ClickSession(
                payload: .click(type: profile.clickType, holdDurationMS: profile.holdDurationMS),
                timing: profile.effectiveTiming)
            session.maxClicks = 1
        case .burst:
            let timing: EffectiveTiming = humanized
                ? .humanized(profile.humanization.timing)
                : .fixed(seconds: profile.speed.burstIntervalMS / 1000)
            session = ClickSession(
                payload: .click(type: profile.clickType, holdDurationMS: profile.holdDurationMS),
                timing: timing)
            session.maxClicks = profile.speed.burstCount
        case .hold, .toggle, .humanizedRapid:
            session = ClickSession(
                payload: .click(type: profile.clickType, holdDurationMS: profile.holdDurationMS),
                timing: profile.effectiveTiming)
        }

        session.targeting = profile.targeting
        session.countdownSeconds = profile.safety.countdownSeconds

        // Safety caps compose with mode-specific caps: the strictest wins.
        if let safetyMax = profile.safety.maxClicks {
            session.maxClicks = session.maxClicks.map { min($0, safetyMax) } ?? safetyMax
        }
        session.maxRuntime = profile.safety.maxRuntimeSeconds

        // Cursor jitter + seed come from whichever humanized config drives
        // the session.
        if profile.mode == .humanizedRapid {
            session.jitterRadius = profile.humanizedRapid.cursorJitterRadius
            session.seed = profile.humanizedRapid.seed
        } else if humanized {
            session.jitterRadius = profile.humanization.timing.cursorJitterRadius
            session.seed = profile.humanization.timing.seed
        }
        return session
    }

    // MARK: UI timer (stats drain)

    private func startUITimer() {
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        uiTimer?.tolerance = 0.05
    }

    private func tick() {
        if isRunning, let start = sessionStart {
            sessionDuration = Date().timeIntervalSince(start)
        }
        drainClickBuffer()

        // Cheap self-heal: while the trigger is armed, make sure the event
        // tap is still alive roughly every 5s. A tap silently disabled by
        // the system would otherwise leave the trigger dead until relaunch.
        if isArmed {
            healthCheckCounter += 1
            if healthCheckCounter >= 33 {
                healthCheckCounter = 0
                monitor.verifyAlive()
            }
        } else {
            healthCheckCounter = 0
        }
    }

    private var healthCheckCounter = 0

    private func drainClickBuffer() {
        clickBufferLock.lock()
        let drained = bufferedClicks
        bufferedClicks.removeAll(keepingCapacity: true)
        clickBufferLock.unlock()
        guard !drained.isEmpty else { return }
        for (_, interval) in drained where interval > 0 {
            stats.record(interval: interval)
        }
        if let last = drained.last {
            let delta = last.count - sessionClicks
            if delta > 0 { lifetimeClicks += delta; statsSessionBase += delta }
            sessionClicks = last.count
        }
    }

    // MARK: Capture flows

    func beginInputDetection() {
        lastDetectedCandidate = nil
        isDetectingInput = true
        syncMonitorConfiguration()
    }

    /// Discard the captured candidate and listen again (used by "Detect
    /// Again" when the user pressed the wrong input).
    func retryInputDetection() {
        lastDetectedCandidate = nil
        isDetectingInput = true
        syncMonitorConfiguration()
    }

    func endInputDetection(assign: Bool) {
        if assign, let trigger = lastDetectedCandidate?.asTrigger {
            updateSelectedProfile { $0.trigger = trigger }
        }
        isDetectingInput = false
        lastDetectedCandidate = nil
        syncMonitorConfiguration()
    }

    private var pointCaptureCompletion: ((CGPoint) -> Void)?

    func beginPointCapture(completion: @escaping (CGPoint) -> Void) {
        pointCaptureCompletion = completion
        isCapturingPoint = true
        syncMonitorConfiguration()
    }

    func cancelPointCapture() {
        pointCaptureCompletion = nil
        isCapturingPoint = false
        syncMonitorConfiguration()
    }

    private func finishPointCapture(with point: CGPoint) {
        let completion = pointCaptureCompletion
        pointCaptureCompletion = nil
        isCapturingPoint = false
        syncMonitorConfiguration()
        completion?(point)
    }

    // MARK: Lifecycle

    /// Called from the app delegate on termination.
    func shutdown() {
        engine.stop(reason: .appTerminating)
        monitor.stop()
        systemEvents.stop()
        uiTimer?.invalidate()
        profileStore.saveNow()
        settingsStore.saveNow()
    }

    // MARK: Display helpers

    var currentCPS: Double { isRunning ? stats.rollingAverageCPS : 0 }

    var emergencyStopDisplay: String {
        settingsStore.settings.emergencyStop.displayName
    }
}
