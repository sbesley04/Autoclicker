import Foundation

/// SplitMix64 — a small, fast, high-quality PRNG used when the user supplies
/// a seed so timing patterns are exactly reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Random value source that is either seeded (reproducible) or backed by the
/// system generator. Reference type so generators can share one stream.
final class RandomSource {
    private var seeded: SplitMix64?
    private var system = SystemRandomNumberGenerator()

    init(seed: UInt64? = nil) {
        seeded = seed.map(SplitMix64.init(seed:))
    }

    /// Uniform in [0, 1).
    func uniform() -> Double {
        if seeded != nil {
            return Double(seeded!.next() >> 11) * (1.0 / 9007199254740992.0)
        }
        return Double(system.next() >> 11) * (1.0 / 9007199254740992.0)
    }

    func uniform(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + uniform() * (range.upperBound - range.lowerBound)
    }

    func chance(_ probability: Double) -> Bool {
        guard probability > 0 else { return false }
        return uniform() < probability
    }

    /// Standard normal sample via Box–Muller.
    func gaussian() -> Double {
        var u1 = uniform()
        if u1 <= Double.leastNormalMagnitude { u1 = Double.leastNormalMagnitude }
        let u2 = uniform()
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }

    /// Normal sample with the given mean/σ, truncated to `range` by
    /// resampling (bounded attempts) and finally clamping. Truncation by
    /// resampling keeps the distribution shape natural near the bounds
    /// instead of piling probability mass onto the clamp edges.
    func truncatedNormal(mean: Double, sigma: Double, in range: ClosedRange<Double>) -> Double {
        guard sigma > 0 else { return mean.clamped(to: range) }
        for _ in 0..<8 {
            let sample = mean + gaussian() * sigma
            if range.contains(sample) { return sample }
        }
        return (mean + gaussian() * sigma).clamped(to: range)
    }
}
