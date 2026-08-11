import SwiftUI

/// Full-window backdrop: near-black base, faint perspective grid, drifting
/// particles and a slow scan line. Every layer is gated by settings and the
/// Reduce Motion environment (via HUDStyle.motion == 0).
struct HUDBackground: View {
    @Environment(\.hudStyle) private var style

    var body: some View {
        ZStack {
            style.palette.background
            LinearGradient(
                colors: [
                    style.accent.opacity(0.06 * style.glow),
                    .clear,
                    style.secondary.opacity(0.05 * style.glow),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            if style.showGrid {
                GridLines()
                    .opacity(0.5)
            }
            if style.showParticles && style.animationsEnabled {
                ParticleField()
                    .allowsHitTesting(false)
            }
            if style.showScanlines {
                ScanlineOverlay()
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Static rectangular grid with a soft radial falloff.
struct GridLines: View {
    @Environment(\.hudStyle) private var style
    var spacing: CGFloat = 42

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(style.accent.opacity(0.05)), lineWidth: 0.5)

            // Brighter major lines every 4 cells.
            var major = Path()
            x = 0
            var index = 0
            while x <= size.width {
                if index % 4 == 0 {
                    major.move(to: CGPoint(x: x, y: 0))
                    major.addLine(to: CGPoint(x: x, y: size.height))
                }
                x += spacing; index += 1
            }
            y = 0; index = 0
            while y <= size.height {
                if index % 4 == 0 {
                    major.move(to: CGPoint(x: 0, y: y))
                    major.addLine(to: CGPoint(x: size.width, y: y))
                }
                y += spacing; index += 1
            }
            context.stroke(major, with: .color(style.accent.opacity(0.09)), lineWidth: 0.5)
        }
        .overlay(
            RadialGradient(
                colors: [.clear, style.palette.background.opacity(0.85)],
                center: .center, startRadius: 100, endRadius: 900)
        )
    }
}

/// A slowly sweeping horizontal scan line plus a static fine-line texture.
struct ScanlineOverlay: View {
    @Environment(\.hudStyle) private var style

    var body: some View {
        ZStack {
            // Static CRT-style micro lines.
            Canvas { context, size in
                var y: CGFloat = 0
                var path = Path()
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 3
                }
                context.stroke(path, with: .color(.black.opacity(0.12)), lineWidth: 1)
            }
            if style.animationsEnabled {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                    GeometryReader { proxy in
                        let height = proxy.size.height
                        let period: Double = 9.0 / max(style.motion, 0.05)
                        let t = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: period) / period
                        LinearGradient(
                            colors: [.clear, style.accent.opacity(0.05 * style.glow), .clear],
                            startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                        .offset(y: CGFloat(t) * (height + 90) - 90)
                    }
                }
            }
        }
    }
}

/// Sparse ambient particles drifting upward.
struct ParticleField: View {
    @Environment(\.hudStyle) private var style

    private struct Particle {
        var x: Double, phase: Double, speed: Double, size: Double, opacity: Double
    }

    private static let particles: [Particle] = {
        var rng = SplitMix64(seed: 0xA07C)
        return (0..<26).map { _ in
            Particle(
                x: Double.random(in: 0...1, using: &rng),
                phase: Double.random(in: 0...1, using: &rng),
                speed: Double.random(in: 0.008...0.03, using: &rng),
                size: Double.random(in: 1...2.6, using: &rng),
                opacity: Double.random(in: 0.15...0.5, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * style.motion
                for particle in Self.particles {
                    let progress = (particle.phase + t * particle.speed)
                        .truncatingRemainder(dividingBy: 1.0)
                    let y = size.height * (1.0 - progress)
                    let x = size.width * particle.x
                        + sin(t * 0.4 + particle.phase * 10) * 12
                    let rect = CGRect(x: x, y: y, width: particle.size, height: particle.size)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(style.accent.opacity(particle.opacity * 0.5 * style.glow)))
                }
            }
        }
    }
}
