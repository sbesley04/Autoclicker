import Foundation

/// Produces the delay before the next click. Implementations must be safe to
/// call from the engine's worker thread (they are only ever used from one
/// thread at a time).
protocol IntervalGenerating: AnyObject {
    /// Next inter-click interval in seconds. Must always be > 0.
    func next() -> TimeInterval
}

/// Constant interval.
final class FixedIntervalGenerator: IntervalGenerating {
    private let interval: TimeInterval

    init(seconds: TimeInterval) {
        interval = max(seconds, SpeedConfig.absoluteMinimumIntervalMS / 1000)
    }

    func next() -> TimeInterval { interval }
}

/// Uniform random interval within a range.
final class UniformRangeGenerator: IntervalGenerating {
    private let range: ClosedRange<TimeInterval>
    private let rng: RandomSource

    init(minSeconds: TimeInterval, maxSeconds: TimeInterval, rng: RandomSource = RandomSource()) {
        let floor = SpeedConfig.absoluteMinimumIntervalMS / 1000
        let lo = max(minSeconds, floor)
        range = lo...max(maxSeconds, lo)
        self.rng = rng
    }

    func next() -> TimeInterval { rng.uniform(in: range) }
}

/// Humanized interval generator.
///
/// Each interval is drawn independently from a truncated normal distribution
/// centred on the target mean, with optional hesitations (occasional longer
/// pauses) and rapid bursts (a few shortened intervals in a row). A gentle
/// drift correction nudges the mean so the long-run average click rate stays
/// close to the configured target even though every sample is random.
final class HumanizedIntervalGenerator: IntervalGenerating {
    private let config: HumanizedTiming
    private let rng: RandomSource
    private let mean: TimeInterval
    private let sigma: TimeInterval
    private let bounds: ClosedRange<TimeInterval>

    private var burstRemaining = 0
    private var emittedSum: TimeInterval = 0
    private var emittedCount = 0

    init(config: HumanizedTiming, rng: RandomSource? = nil) {
        let cfg = config.sanitized()
        self.config = cfg
        self.rng = rng ?? RandomSource(seed: cfg.seed)
        let floor = SpeedConfig.absoluteMinimumIntervalMS / 1000
        let lo = max(cfg.minIntervalMS / 1000, floor)
        let hi = max(cfg.maxIntervalMS / 1000, lo)
        bounds = lo...hi
        mean = (1.0 / max(cfg.targetCPS, 0.001)).clamped(to: bounds)
        sigma = mean * (cfg.variationPercent / 100) * cfg.intensity.sigmaMultiplier
    }

    func next() -> TimeInterval {
        var interval: TimeInterval

        if burstRemaining > 0 {
            // Inside a rapid burst: intervals sit near the lower bound with a
            // little jitter, so bursts feel quick but not machine-perfect.
            burstRemaining -= 1
            let burstTarget = bounds.lowerBound + (mean - bounds.lowerBound) * 0.35
            interval = rng.truncatedNormal(mean: burstTarget, sigma: sigma * 0.5, in: bounds)
        } else if rng.chance(config.hesitationProbability) {
            // Brief hesitation: noticeably longer than the mean, still bounded.
            interval = rng.uniform(in: (mean * 1.7)...(mean * 3.0)).clamped(to: bounds)
        } else if rng.chance(config.burstProbability), config.burstLength > 1 {
            burstRemaining = config.burstLength - 1
            let burstTarget = bounds.lowerBound + (mean - bounds.lowerBound) * 0.35
            interval = rng.truncatedNormal(mean: burstTarget, sigma: sigma * 0.5, in: bounds)
        } else {
            // Drift correction: shift the sampling mean by a fraction of the
            // accumulated error so the rolling average tracks the target
            // without ever creating an obviously repeating pattern.
            var center = mean
            if emittedCount > 0 {
                let expected = mean * Double(emittedCount)
                let error = expected - emittedSum // positive → we're running fast
                center = (mean + (error / Double(max(emittedCount, 8))) * 0.6).clamped(to: bounds)
            }
            interval = rng.truncatedNormal(mean: center, sigma: sigma, in: bounds)
        }

        // Absolute guarantees, independent of the branch above.
        interval = interval.clamped(to: bounds)
        emittedSum += interval
        emittedCount += 1
        return interval
    }
}

/// Builds the correct generator for a resolved timing strategy.
enum IntervalGeneratorFactory {
    static func make(for timing: EffectiveTiming) -> IntervalGenerating {
        switch timing {
        case .fixed(let seconds):
            return FixedIntervalGenerator(seconds: seconds)
        case .uniformRange(let minSeconds, let maxSeconds):
            return UniformRangeGenerator(minSeconds: minSeconds, maxSeconds: maxSeconds)
        case .humanized(let config):
            return HumanizedIntervalGenerator(config: config)
        }
    }
}
