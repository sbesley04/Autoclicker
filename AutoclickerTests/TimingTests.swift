import Foundation
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

@Suite("Interval calculation")
struct IntervalCalculationTests {
    @Test("CPS converts to the expected interval")
    func cpsConversion() {
        var speed = SpeedConfig()
        speed.mode = .clicksPerSecond
        speed.clicksPerSecond = 20
        #expect(abs(speed.nominalIntervalMS - 50) < 0.001)
        speed.clicksPerSecond = 0.5 // decimal CPS supported
        #expect(abs(speed.nominalIntervalMS - 2000) < 0.001)
    }

    @Test("Fixed generator returns constant positive intervals")
    func fixedGenerator() {
        let generator = FixedIntervalGenerator(seconds: 0.125)
        for _ in 0..<10 {
            #expect(generator.next() == 0.125)
        }
    }

    @Test("Negative and zero intervals are clamped to a positive floor")
    func noNonPositiveIntervals() {
        #expect(FixedIntervalGenerator(seconds: 0).next() > 0)
        #expect(FixedIntervalGenerator(seconds: -3).next() > 0)
        let uniform = UniformRangeGenerator(minSeconds: -1, maxSeconds: -0.5)
        for _ in 0..<50 { #expect(uniform.next() > 0) }
        var config = HumanizedTiming()
        config.minIntervalMS = 0
        config.maxIntervalMS = 0
        let humanized = HumanizedIntervalGenerator(config: config)
        for _ in 0..<50 { #expect(humanized.next() > 0) }
    }

    @Test("Uniform range generator honors its bounds")
    func uniformRangeBounds() {
        let generator = UniformRangeGenerator(minSeconds: 0.05, maxSeconds: 0.1,
                                              rng: RandomSource(seed: 7))
        for _ in 0..<500 {
            let interval = generator.next()
            #expect(interval >= 0.05 && interval <= 0.1)
        }
    }

    @Test("Speed validation flags min greater than max")
    func speedValidation() {
        var speed = SpeedConfig()
        speed.mode = .randomRange
        speed.randomMinMS = 500
        speed.randomMaxMS = 100
        #expect(!speed.validationIssues().isEmpty)
        let sanitized = speed.sanitized()
        #expect(sanitized.randomMinMS <= sanitized.randomMaxMS)
    }
}

@Suite("Humanized timing")
struct HumanizedTimingTests {
    private func config(
        cps: Double = 10,
        min: Double = 20,
        max: Double = 400,
        seed: UInt64? = 99
    ) -> HumanizedTiming {
        var c = HumanizedTiming()
        c.targetCPS = cps
        c.minIntervalMS = min
        c.maxIntervalMS = max
        c.seed = seed
        return c
    }

    @Test("Every interval respects the configured bounds")
    func intervalBounds() {
        var c = config(cps: 12, min: 40, max: 250)
        c.intensity = .strong
        c.variationPercent = 50
        c.hesitationProbability = 0.15
        c.burstProbability = 0.25
        let generator = HumanizedIntervalGenerator(config: c)
        for _ in 0..<5000 {
            let interval = generator.next()
            #expect(interval >= 0.040 - 1e-9)
            #expect(interval <= 0.250 + 1e-9)
        }
    }

    @Test("Consecutive intervals differ (no fixed pattern)")
    func intervalsVary() {
        let generator = HumanizedIntervalGenerator(config: config())
        var values = Set<Int>()
        for _ in 0..<100 {
            values.insert(Int(generator.next() * 1_000_000))
        }
        // With genuine per-click randomness nearly all values are distinct.
        #expect(values.count > 60)
    }

    @Test("Long-run average stays close to the target CPS")
    func longRunAverage() {
        let c = config(cps: 20, min: 10, max: 200, seed: 4242)
        let generator = HumanizedIntervalGenerator(config: c)
        var total: TimeInterval = 0
        let count = 4000
        for _ in 0..<count { total += generator.next() }
        let averageCPS = Double(count) / total
        #expect(abs(averageCPS - 20) / 20 < 0.10, "average was \(averageCPS)")
    }

    @Test("Seeded generation is exactly reproducible")
    func seededReproducibility() {
        let a = HumanizedIntervalGenerator(config: config(seed: 1234))
        let b = HumanizedIntervalGenerator(config: config(seed: 1234))
        for _ in 0..<300 {
            #expect(a.next() == b.next())
        }
        let c = HumanizedIntervalGenerator(config: config(seed: 1235))
        var identical = true
        let d = HumanizedIntervalGenerator(config: config(seed: 1234))
        for _ in 0..<50 where c.next() != d.next() { identical = false }
        #expect(!identical)
    }

    @Test("Subtle profile varies less than strong custom settings")
    func profileIntensities() {
        func stddev(_ profile: HumanizationProfile, intensity: VariationIntensity) -> Double {
            var c = config(seed: 777)
            c.applyProfile(profile)
            c.intensity = intensity
            c.hesitationProbability = 0
            c.burstProbability = 0
            let generator = HumanizedIntervalGenerator(config: c)
            var samples: [Double] = []
            for _ in 0..<1500 { samples.append(generator.next()) }
            let mean = samples.reduce(0, +) / Double(samples.count)
            let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)
            return variance.squareRoot()
        }
        let subtle = stddev(.subtle, intensity: .subtle)
        let strong = stddev(.custom, intensity: .strong)
        #expect(subtle < strong)
    }

    @Test("Subtle profile produces no long pauses")
    func subtleNoPauses() {
        var c = config(cps: 10, min: 40, max: 500, seed: 31)
        c.applyProfile(.subtle)
        let generator = HumanizedIntervalGenerator(config: c)
        let mean = 0.1
        for _ in 0..<2000 {
            // Subtle variation should stay well under 2× the mean interval.
            #expect(generator.next() < mean * 2)
        }
    }

    @Test("Burst profile produces more near-minimum intervals than subtle")
    func burstBehavior() {
        func fastFraction(_ profile: HumanizationProfile) -> Double {
            var c = config(cps: 8, min: 30, max: 600, seed: 55)
            c.applyProfile(profile)
            let generator = HumanizedIntervalGenerator(config: c)
            var fast = 0
            let n = 3000
            for _ in 0..<n where generator.next() < 0.06 { fast += 1 }
            return Double(fast) / Double(n)
        }
        #expect(fastFraction(.burst) > fastFraction(.subtle))
    }

    @Test("Validation rejects min interval above max interval")
    func invalidBounds() {
        var c = config(min: 500, max: 100)
        #expect(!c.validationIssues().isEmpty)
        c = c.sanitized()
        #expect(c.minIntervalMS <= c.maxIntervalMS)
        #expect(c.validationIssues().isEmpty == (c.meanIntervalMS >= c.minIntervalMS && c.meanIntervalMS <= c.maxIntervalMS))
    }

    @Test("Target speed outside the bounds is reported")
    func targetOutsideBounds() {
        // 2 cps → 500 ms mean, but max is 200 ms: impossible to average.
        let c = config(cps: 2, min: 50, max: 200)
        #expect(!c.validationIssues().isEmpty)
    }
}

@Suite("Timing preview")
struct TimingPreviewTests {
    @Test("Preview simulates the requested number of intervals with no event posting")
    func previewSimulation() {
        var c = HumanizedTiming()
        c.targetCPS = 10
        c.minIntervalMS = 50
        c.maxIntervalMS = 300
        c.seed = 12
        let result = TimingPreview.simulate(config: c, count: 120)
        #expect(result.count == 120)
        #expect(result.intervals.allSatisfy { $0 >= 0.05 && $0 <= 0.3 })
        #expect(result.averageCPS > 0)
        #expect(result.minInterval <= result.maxInterval)
    }

    @Test("Preview with a seed matches the live generator's pattern")
    func previewMatchesGenerator() {
        var c = HumanizedTiming()
        c.seed = 900
        let preview = TimingPreview.simulate(config: c, count: 50)
        let generator = HumanizedIntervalGenerator(config: c)
        for interval in preview.intervals {
            #expect(interval == generator.next())
        }
    }

    @Test("Interval statistics track min, max and averages")
    func statistics() {
        var stats = IntervalStatistics(capacity: 10)
        for interval in [0.1, 0.2, 0.3] { stats.record(interval: interval) }
        #expect(stats.totalCount == 3)
        #expect(abs(stats.minObserved - 0.1) < 1e-9)
        #expect(abs(stats.maxObserved - 0.3) < 1e-9)
        #expect(abs(stats.rollingAverageCPS - 1 / 0.2) < 0.001)
        #expect(stats.recentVariation > 0)
        // Capacity is enforced.
        for _ in 0..<50 { stats.record(interval: 0.05) }
        #expect(stats.recentIntervals.count == 10)
    }
}
