import Foundation
import CoreGraphics

// MARK: - Speed

enum SpeedMode: String, Codable, CaseIterable, Identifiable {
    case clicksPerSecond
    case fixedInterval
    case randomRange
    case humanized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clicksPerSecond: return "Clicks / Second"
        case .fixedInterval: return "Fixed Interval"
        case .randomRange: return "Random Range"
        case .humanized: return "Humanized"
        }
    }
}

struct SpeedConfig: Codable, Equatable {
    /// Hard engine floor — nothing may click faster than this (1000 CPS).
    static let absoluteMinimumIntervalMS: Double = 1.0
    /// Rates above this ask for confirmation when safety option is on.
    static let highRateThresholdCPS: Double = 30.0

    var mode: SpeedMode = .clicksPerSecond
    /// Used by `.clicksPerSecond`. Decimal values allowed (e.g. 0.2 CPS).
    var clicksPerSecond: Double = 10
    /// Used by `.fixedInterval`, in milliseconds.
    var intervalMS: Double = 100
    /// Used by `.randomRange`, in milliseconds.
    var randomMinMS: Double = 80
    var randomMaxMS: Double = 160
    /// Burst mode: number of clicks per activation and spacing.
    var burstCount: Int = 10
    var burstIntervalMS: Double = 50

    /// The nominal average interval for display purposes.
    var nominalIntervalMS: Double {
        switch mode {
        case .clicksPerSecond: return 1000.0 / max(clicksPerSecond, 0.001)
        case .fixedInterval: return intervalMS
        case .randomRange: return (randomMinMS + randomMaxMS) / 2
        case .humanized: return 0 // provided by HumanizedTiming
        }
    }

    var nominalCPS: Double {
        let ms = nominalIntervalMS
        return ms > 0 ? 1000.0 / ms : 0
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        switch mode {
        case .clicksPerSecond:
            if clicksPerSecond <= 0 { issues.append("Clicks per second must be greater than zero.") }
            if 1000.0 / max(clicksPerSecond, 0.001) < Self.absoluteMinimumIntervalMS {
                issues.append("Rate exceeds the engine maximum of 1000 clicks per second.")
            }
        case .fixedInterval:
            if intervalMS < Self.absoluteMinimumIntervalMS {
                issues.append("Interval must be at least \(Int(Self.absoluteMinimumIntervalMS)) ms.")
            }
        case .randomRange:
            if randomMinMS < Self.absoluteMinimumIntervalMS {
                issues.append("Minimum interval must be at least \(Int(Self.absoluteMinimumIntervalMS)) ms.")
            }
            if randomMinMS > randomMaxMS {
                issues.append("Minimum interval is greater than maximum interval.")
            }
        case .humanized:
            break // validated by HumanizedTiming
        }
        if burstCount < 1 { issues.append("Burst count must be at least 1.") }
        if burstIntervalMS < Self.absoluteMinimumIntervalMS {
            issues.append("Burst interval must be at least \(Int(Self.absoluteMinimumIntervalMS)) ms.")
        }
        return issues
    }

    /// Returns a copy with every value forced into a safe range. Used when
    /// loading persisted or imported data so a corrupt profile can't produce
    /// a runaway click loop.
    func sanitized() -> SpeedConfig {
        var copy = self
        copy.clicksPerSecond = clicksPerSecond.clamped(to: 0.01...1000)
        copy.intervalMS = intervalMS.clamped(to: Self.absoluteMinimumIntervalMS...3_600_000)
        copy.randomMinMS = randomMinMS.clamped(to: Self.absoluteMinimumIntervalMS...3_600_000)
        copy.randomMaxMS = randomMaxMS.clamped(to: copy.randomMinMS...3_600_000)
        copy.burstCount = burstCount.clamped(to: 1...100_000)
        copy.burstIntervalMS = burstIntervalMS.clamped(to: Self.absoluteMinimumIntervalMS...600_000)
        return copy
    }
}

// MARK: - Humanized timing

enum HumanizationProfile: String, Codable, CaseIterable, Identifiable {
    case subtle
    case natural
    case burst
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .natural: return "Natural"
        case .burst: return "Burst"
        case .custom: return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .subtle: return "Very small interval changes close to the target speed"
        case .natural: return "Moderate variation resembling rapid manual clicking"
        case .burst: return "Alternates short rapid groups with brief pauses"
        case .custom: return "All probability and interval controls exposed"
        }
    }
}

enum VariationIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle
    case moderate
    case strong

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Multiplier applied to the base standard deviation.
    var sigmaMultiplier: Double {
        switch self {
        case .subtle: return 0.45
        case .moderate: return 1.0
        case .strong: return 1.8
        }
    }
}

/// Configuration shared by the optional humanization system and the dedicated
/// Humanized Rapid mode. All features default to OFF / neutral values.
struct HumanizedTiming: Codable, Equatable {
    var profile: HumanizationProfile = .natural
    /// Target average clicks per second.
    var targetCPS: Double = 8
    /// Timing variation as a percentage of the mean interval (std-dev).
    var variationPercent: Double = 18
    /// Hard bounds on every generated interval, in milliseconds.
    var minIntervalMS: Double = 40
    var maxIntervalMS: Double = 450
    var intensity: VariationIntensity = .moderate
    /// Probability [0, 1] of an occasional brief hesitation (longer pause).
    var hesitationProbability: Double = 0.0
    /// Probability [0, 1] of entering a short rapid burst.
    var burstProbability: Double = 0.0
    /// Number of clicks in a rapid burst.
    var burstLength: Int = 4
    /// Optional cursor position jitter radius in points (0 = off).
    var cursorJitterRadius: Double = 0
    /// Optional random seed for reproducible patterns (nil = system entropy).
    var seed: UInt64? = nil

    var meanIntervalMS: Double { 1000.0 / max(targetCPS, 0.001) }

    /// Applies a named preset's characteristic parameters, preserving the
    /// user's target speed and bounds.
    mutating func applyProfile(_ p: HumanizationProfile) {
        profile = p
        switch p {
        case .subtle:
            variationPercent = 7
            intensity = .subtle
            hesitationProbability = 0
            burstProbability = 0
        case .natural:
            variationPercent = 18
            intensity = .moderate
            hesitationProbability = 0.03
            burstProbability = 0.02
        case .burst:
            variationPercent = 14
            intensity = .moderate
            hesitationProbability = 0.05
            burstProbability = 0.18
            burstLength = 5
        case .custom:
            break // leave everything as-is
        }
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if targetCPS <= 0 { issues.append("Target clicks per second must be greater than zero.") }
        if minIntervalMS < SpeedConfig.absoluteMinimumIntervalMS {
            issues.append("Minimum interval must be at least \(Int(SpeedConfig.absoluteMinimumIntervalMS)) ms.")
        }
        if minIntervalMS > maxIntervalMS {
            issues.append("Minimum interval is greater than maximum interval.")
        }
        if meanIntervalMS < minIntervalMS || meanIntervalMS > maxIntervalMS {
            issues.append("Target speed (\(String(format: "%.0f", meanIntervalMS)) ms average) lies outside the min/max interval bounds.")
        }
        if !(0...1).contains(hesitationProbability) { issues.append("Hesitation probability must be between 0 and 1.") }
        if !(0...1).contains(burstProbability) { issues.append("Burst probability must be between 0 and 1.") }
        if burstLength < 1 { issues.append("Burst length must be at least 1.") }
        return issues
    }

    func sanitized() -> HumanizedTiming {
        var copy = self
        copy.targetCPS = targetCPS.clamped(to: 0.05...1000)
        copy.minIntervalMS = minIntervalMS.clamped(to: SpeedConfig.absoluteMinimumIntervalMS...60_000)
        copy.maxIntervalMS = maxIntervalMS.clamped(to: copy.minIntervalMS...600_000)
        copy.variationPercent = variationPercent.clamped(to: 0...100)
        copy.hesitationProbability = hesitationProbability.clamped(to: 0...1)
        copy.burstProbability = burstProbability.clamped(to: 0...1)
        copy.burstLength = burstLength.clamped(to: 1...50)
        copy.cursorJitterRadius = cursorJitterRadius.clamped(to: 0...100)
        return copy
    }
}

/// Master switch + settings for the optional humanization system attached to
/// the standard modes (hold / toggle / burst / sequences).
struct HumanizationConfig: Codable, Equatable {
    /// Disabled by default, as required.
    var enabled: Bool = false
    var timing: HumanizedTiming = HumanizedTiming()

    func validationIssues() -> [String] {
        enabled ? timing.validationIssues() : []
    }

    func sanitized() -> HumanizationConfig {
        var copy = self
        copy.timing = timing.sanitized()
        return copy
    }
}

// MARK: - Targeting

struct SavedPoint: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "Point"
    /// Stored in CoreGraphics global coordinates (origin top-left of the
    /// main display) so they can be fed straight into CGEvent.
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

enum TargetingMode: String, Codable, CaseIterable, Identifiable {
    case currentCursor
    case fixedPoint
    case cyclePoints
    case randomPoint

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentCursor: return "Current Cursor"
        case .fixedPoint: return "Saved Point"
        case .cyclePoints: return "Cycle Points"
        case .randomPoint: return "Random Point"
        }
    }

    var summary: String {
        switch self {
        case .currentCursor: return "Click wherever the cursor currently is"
        case .fixedPoint: return "Click at one saved screen coordinate"
        case .cyclePoints: return "Cycle through the saved coordinates in order"
        case .randomPoint: return "Pick a random saved coordinate each click"
        }
    }

    var usesSavedPoints: Bool { self != .currentCursor }
}

struct TargetingConfig: Codable, Equatable {
    var mode: TargetingMode = .currentCursor
    var points: [SavedPoint] = []
    /// Return the cursor to where it was before the session started.
    var returnToOrigin: Bool = false

    func validationIssues() -> [String] {
        if mode.usesSavedPoints && points.isEmpty {
            return ["\(mode.displayName) targeting needs at least one saved point."]
        }
        return []
    }
}

// MARK: - Safety

struct SafetyConfig: Codable, Equatable {
    /// nil = unlimited.
    var maxClicks: Int? = nil
    /// nil = unlimited, otherwise seconds.
    var maxRuntimeSeconds: Double? = nil
    /// Delay before clicking starts (0 = immediate).
    var countdownSeconds: Double = 0
    /// Stop when the frontmost application changes.
    var stopOnAppSwitch: Bool = false
    /// Ask for confirmation before starting at very high click rates.
    var confirmHighRates: Bool = true

    func validationIssues() -> [String] {
        var issues: [String] = []
        if let m = maxClicks, m < 1 { issues.append("Maximum click count must be at least 1.") }
        if let r = maxRuntimeSeconds, r <= 0 { issues.append("Maximum runtime must be greater than zero.") }
        if countdownSeconds < 0 || countdownSeconds > 60 { issues.append("Countdown must be between 0 and 60 seconds.") }
        return issues
    }

    func sanitized() -> SafetyConfig {
        var copy = self
        if let m = maxClicks { copy.maxClicks = max(1, m) }
        if let r = maxRuntimeSeconds { copy.maxRuntimeSeconds = max(0.1, r) }
        copy.countdownSeconds = countdownSeconds.clamped(to: 0...60)
        return copy
    }
}

// MARK: - Clamping helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
