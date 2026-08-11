import Foundation

/// A complete, self-contained autoclicker configuration.
struct Profile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "New Profile"
    /// Theme accent override for this profile (nil = app theme).
    var accentThemeID: String? = nil

    var trigger: TriggerInput = .none
    var inputBehavior: InputBehavior = .passThrough
    var mode: ActivationMode = .toggle
    var clickType: ClickType = .left
    /// Duration for `.clickAndHold`, in milliseconds.
    var holdDurationMS: Double = 500

    var speed: SpeedConfig = SpeedConfig()
    /// Optional humanization layered onto hold / toggle / burst / sequences.
    var humanization: HumanizationConfig = HumanizationConfig()
    /// Dedicated timing settings for Humanized Rapid mode.
    var humanizedRapid: HumanizedTiming = {
        var t = HumanizedTiming()
        t.applyProfile(.natural)
        return t
    }()
    var targeting: TargetingConfig = TargetingConfig()
    var sequence: [SequenceStep] = []
    var safety: SafetyConfig = SafetyConfig()

    // MARK: Derived

    /// True when this profile executes the action sequence instead of a
    /// single click type.
    var usesSequence: Bool {
        mode == .repeatSequence || (mode == .oneShot && !sequence.isEmpty)
    }

    /// The timing configuration that will actually drive the engine.
    var effectiveTiming: EffectiveTiming {
        if mode == .humanizedRapid {
            return .humanized(humanizedRapid)
        }
        if humanization.enabled {
            return .humanized(humanization.timing)
        }
        switch speed.mode {
        case .clicksPerSecond: return .fixed(seconds: 1.0 / max(speed.clicksPerSecond, 0.001))
        case .fixedInterval: return .fixed(seconds: speed.intervalMS / 1000)
        case .randomRange: return .uniformRange(minSeconds: speed.randomMinMS / 1000, maxSeconds: speed.randomMaxMS / 1000)
        case .humanized: return .humanized(humanization.timing)
        }
    }

    /// Estimated average clicks per second for display before starting.
    var estimatedCPS: Double {
        switch effectiveTiming {
        case .fixed(let s): return s > 0 ? 1 / s : 0
        case .uniformRange(let a, let b):
            let avg = (a + b) / 2
            return avg > 0 ? 1 / avg : 0
        case .humanized(let t): return t.targetCPS
        }
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Profile name cannot be empty.")
        }
        issues += speed.validationIssues()
        issues += humanization.validationIssues()
        if mode == .humanizedRapid { issues += humanizedRapid.validationIssues() }
        issues += targeting.validationIssues()
        issues += safety.validationIssues()
        if usesSequence {
            issues += SequenceValidator.validate(sequence)
                .filter { $0.severity == .error }
                .map(\.message)
        }
        return issues
    }

    /// Clamp all values into safe ranges. Applied to loaded/imported data.
    func sanitized() -> Profile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = "Recovered Profile" }
        copy.holdDurationMS = holdDurationMS.clamped(to: 10...600_000)
        copy.speed = speed.sanitized()
        copy.humanization = humanization.sanitized()
        copy.humanizedRapid = humanizedRapid.sanitized()
        copy.safety = safety.sanitized()
        return copy
    }
}

/// Resolved timing strategy for a session.
enum EffectiveTiming: Equatable {
    case fixed(seconds: TimeInterval)
    case uniformRange(minSeconds: TimeInterval, maxSeconds: TimeInterval)
    case humanized(HumanizedTiming)
}

// MARK: - Default presets

extension Profile {
    static func defaultProfiles() -> [Profile] {
        [rapidClick, precisionClick, holdToClick, controlledBurst, humanizedPreset, coordinateCycle]
    }

    static var rapidClick: Profile {
        var p = Profile()
        p.name = "Rapid Click"
        p.mode = .toggle
        p.clickType = .left
        p.speed.mode = .clicksPerSecond
        p.speed.clicksPerSecond = 20
        p.accentThemeID = HUDThemeID.neonCyan.rawValue
        return p
    }

    static var precisionClick: Profile {
        var p = Profile()
        p.name = "Precision Click"
        p.mode = .oneShot
        p.clickType = .left
        p.speed.mode = .fixedInterval
        p.speed.intervalMS = 1000
        p.safety.countdownSeconds = 3
        p.accentThemeID = HUDThemeID.electricViolet.rawValue
        return p
    }

    static var holdToClick: Profile {
        var p = Profile()
        p.name = "Hold to Click"
        p.mode = .hold
        p.clickType = .left
        p.speed.mode = .clicksPerSecond
        p.speed.clicksPerSecond = 12
        p.accentThemeID = HUDThemeID.matrixGreen.rawValue
        return p
    }

    static var controlledBurst: Profile {
        var p = Profile()
        p.name = "Controlled Burst"
        p.mode = .burst
        p.clickType = .left
        p.speed.burstCount = 15
        p.speed.burstIntervalMS = 40
        p.safety.maxClicks = 1500
        p.accentThemeID = HUDThemeID.solarOrange.rawValue
        return p
    }

    static var humanizedPreset: Profile {
        var p = Profile()
        p.name = "Humanized"
        p.mode = .humanizedRapid
        p.clickType = .left
        p.humanizedRapid.targetCPS = 7
        p.humanizedRapid.applyProfile(.natural)
        p.humanizedRapid.minIntervalMS = 60
        p.humanizedRapid.maxIntervalMS = 420
        p.accentThemeID = HUDThemeID.plasmaMagenta.rawValue
        return p
    }

    static var coordinateCycle: Profile {
        var p = Profile()
        p.name = "Coordinate Cycle"
        p.mode = .toggle
        p.clickType = .left
        p.speed.mode = .fixedInterval
        p.speed.intervalMS = 500
        p.targeting.mode = .cyclePoints
        p.targeting.returnToOrigin = true
        p.accentThemeID = HUDThemeID.electricBlue.rawValue
        return p
    }
}
