import Foundation

/// Simulates a humanized timing pattern without generating any mouse events.
/// Used by the Humanization screen's preview graph and by tests.
enum TimingPreview {
    struct Result: Equatable {
        var intervals: [TimeInterval]

        var count: Int { intervals.count }
        var averageInterval: TimeInterval {
            intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        }
        var averageCPS: Double {
            let avg = averageInterval
            return avg > 0 ? 1 / avg : 0
        }
        var minInterval: TimeInterval { intervals.min() ?? 0 }
        var maxInterval: TimeInterval { intervals.max() ?? 0 }
    }

    /// Generate `count` simulated intervals. Pure computation — this never
    /// touches CGEvent or any input APIs.
    static func simulate(config: HumanizedTiming, count: Int) -> Result {
        let generator = HumanizedIntervalGenerator(config: config)
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(max(count, 0))
        for _ in 0..<max(count, 0) {
            intervals.append(generator.next())
        }
        return Result(intervals: intervals)
    }
}

/// Rolling statistics over recent click intervals, driving the live
/// Humanized Rapid visualization. Pure value type; the UI owns an instance
/// on the main actor.
struct IntervalStatistics: Equatable {
    private(set) var recentIntervals: [TimeInterval] = []
    private(set) var minObserved: TimeInterval = .infinity
    private(set) var maxObserved: TimeInterval = 0
    private(set) var totalCount: Int = 0
    private(set) var totalSum: TimeInterval = 0
    let capacity: Int

    init(capacity: Int = 120) {
        self.capacity = capacity
    }

    mutating func record(interval: TimeInterval) {
        recentIntervals.append(interval)
        if recentIntervals.count > capacity {
            recentIntervals.removeFirst(recentIntervals.count - capacity)
        }
        minObserved = min(minObserved, interval)
        maxObserved = max(maxObserved, interval)
        totalCount += 1
        totalSum += interval
    }

    mutating func reset() {
        recentIntervals.removeAll()
        minObserved = .infinity
        maxObserved = 0
        totalCount = 0
        totalSum = 0
    }

    var lastInterval: TimeInterval? { recentIntervals.last }

    /// Instantaneous CPS from the most recent interval.
    var currentCPS: Double {
        guard let last = recentIntervals.last, last > 0 else { return 0 }
        return 1 / last
    }

    /// Rolling average CPS over the recent window.
    var rollingAverageCPS: Double {
        guard !recentIntervals.isEmpty else { return 0 }
        let avg = recentIntervals.reduce(0, +) / Double(recentIntervals.count)
        return avg > 0 ? 1 / avg : 0
    }

    /// Average CPS over the whole session.
    var sessionAverageCPS: Double {
        guard totalCount > 0, totalSum > 0 else { return 0 }
        return Double(totalCount) / totalSum
    }

    /// Standard deviation of the recent window, for the variation readout.
    var recentVariation: TimeInterval {
        guard recentIntervals.count > 1 else { return 0 }
        let mean = recentIntervals.reduce(0, +) / Double(recentIntervals.count)
        let variance = recentIntervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(recentIntervals.count - 1)
        return variance.squareRoot()
    }
}
