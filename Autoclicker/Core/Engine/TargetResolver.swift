import Foundation
import CoreGraphics

/// Decides where each click lands, implementing the targeting modes and
/// optional cursor jitter. One instance lives per session (worker thread).
final class TargetResolver {
    private let config: TargetingConfig
    private let jitterRadius: Double
    private let rng: RandomSource
    private unowned let poster: EventPosting
    private var cycleIndex = 0

    init(config: TargetingConfig, jitterRadius: Double, rng: RandomSource, poster: EventPosting) {
        self.config = config
        self.jitterRadius = jitterRadius
        self.rng = rng
        self.poster = poster
    }

    func nextPoint() -> CGPoint {
        var point: CGPoint
        switch config.mode {
        case .currentCursor:
            point = poster.currentLocation
        case .fixedPoint:
            point = config.points.first?.cgPoint ?? poster.currentLocation
        case .cyclePoints:
            guard !config.points.isEmpty else { return poster.currentLocation }
            point = config.points[cycleIndex % config.points.count].cgPoint
            cycleIndex += 1
        case .randomPoint:
            guard !config.points.isEmpty else { return poster.currentLocation }
            let index = Int(rng.uniform() * Double(config.points.count))
            point = config.points[min(index, config.points.count - 1)].cgPoint
        }
        if jitterRadius > 0 {
            // Uniform sample inside a disc for natural-looking spread.
            let angle = rng.uniform(in: 0...(2 * .pi))
            let radius = jitterRadius * rng.uniform().squareRoot()
            point.x += cos(angle) * radius
            point.y += sin(angle) * radius
        }
        return point
    }
}
