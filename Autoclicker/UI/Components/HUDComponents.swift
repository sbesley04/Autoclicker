import SwiftUI

// MARK: - Angular panel shape

/// Rounded rectangle with two clipped corners for the angular HUD look.
struct AngularPanel: Shape {
    var cut: CGFloat = 12
    var radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel modifier

struct HUDPanelModifier: ViewModifier {
    @Environment(\.hudStyle) private var style
    var accented: Bool = false

    func body(content: Content) -> some View {
        let shape = AngularPanel()
        return content
            .padding(style.compact ? 12 : 16)
            .background(
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [style.palette.panelHighlight, style.palette.panel],
                            startPoint: .top, endPoint: .bottom))
                    // Subtle inner glass sheen.
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.045), .clear],
                            startPoint: .top, endPoint: .center))
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                style.accent.opacity(accented ? 0.75 : 0.32),
                                style.accent.opacity(accented ? 0.3 : 0.1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                }
            )
            .shadow(color: style.accent.opacity(0.16 * style.glow), radius: style.glowRadius(accented ? 14 : 8))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}

extension View {
    func hudPanel(accented: Bool = false) -> some View {
        modifier(HUDPanelModifier(accented: accented))
    }
}

// MARK: - Typography helpers

struct HUDSectionHeader: View {
    @Environment(\.hudStyle) private var style
    var title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(style.palette.textSecondary)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [style.accent.opacity(0.5), .clear],
                        startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small monospaced value readout with a label underneath.
struct HUDStat: View {
    @Environment(\.hudStyle) private var style
    var label: String
    var value: String
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(color ?? style.palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(style.palette.textDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Colored status dot + label; shape varies with state so status never
/// relies on color alone.
struct StatusIndicator: View {
    @Environment(\.hudStyle) private var style
    enum State { case good, warning, bad, neutral }
    var state: State
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.8 * style.glow), radius: style.glowRadius(4))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(style.palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(accessibilityState)")
    }

    private var symbol: String {
        switch state {
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        case .neutral: return "circle.dotted"
        }
    }

    private var color: Color {
        switch state {
        case .good: return style.palette.good
        case .warning: return style.palette.warning
        case .bad: return style.palette.danger
        case .neutral: return style.palette.textDim
        }
    }

    private var accessibilityState: String {
        switch state {
        case .good: return "OK"
        case .warning: return "warning"
        case .bad: return "problem"
        case .neutral: return "inactive"
        }
    }
}

// MARK: - Buttons

/// Primary angular neon button.
struct HUDButtonStyle: ButtonStyle {
    @Environment(\.hudStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    var role: Role = .normal
    var prominent: Bool = false

    enum Role { case normal, destructive }

    func makeBody(configuration: Configuration) -> some View {
        let color = role == .destructive ? style.palette.danger : style.accent
        let shape = AngularPanel(cut: 8, radius: 4)
        return configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundStyle(prominent ? style.palette.background : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if prominent {
                        shape.fill(color.opacity(configuration.isPressed ? 0.75 : 0.92))
                    } else {
                        shape.fill(color.opacity(configuration.isPressed ? 0.22 : 0.09))
                    }
                    shape.stroke(color.opacity(0.75), lineWidth: 1)
                }
            )
            .shadow(color: color.opacity((configuration.isPressed ? 0.5 : 0.28) * style.glow),
                    radius: style.glowRadius(8))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && style.animationsEnabled ? 0.97 : 1)
            .animation(style.animationsEnabled ? .easeOut(duration: 0.12) : nil,
                       value: configuration.isPressed)
            .contentShape(shape)
    }
}

// MARK: - Status ring

/// Radial ring with tick marks; fills and pulses while running.
struct StatusRing: View {
    @Environment(\.hudStyle) private var style
    var active: Bool
    /// 0…1 progress (e.g. toward a click limit); nil = indeterminate spin.
    var progress: Double? = nil
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            if active && style.animationsEnabled {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    ring(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                ring(at: 0)
            }
        }
        .frame(width: size, height: size)
    }

    private func ring(at t: TimeInterval) -> some View {
        let color: Color = active ? style.accent : style.palette.textDim
        let pulse: Double = active && style.animationsEnabled
            ? 0.75 + 0.25 * sin(t * 3.2) : 1.0
        let shadowColor: Color = color.opacity((active ? 0.5 : 0.1) * style.glow)
        return ringCanvas(t: t, color: color, pulse: pulse)
            .shadow(color: shadowColor, radius: style.glowRadius(12))
            .accessibilityHidden(true)
    }

    private func ringCanvas(t: TimeInterval, color: Color, pulse: Double) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 8

            // Tick marks.
            for i in 0..<60 {
                let angle: CGFloat = CGFloat(i) / 60.0 * 2.0 * CGFloat.pi - CGFloat.pi / 2.0
                let isMajor: Bool = i % 5 == 0
                let inner: CGFloat = radius - (isMajor ? 8.0 : 4.0)
                let cosA: CGFloat = cos(angle)
                let sinA: CGFloat = sin(angle)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cosA * inner,
                                      y: center.y + sinA * inner))
                tick.addLine(to: CGPoint(x: center.x + cosA * radius,
                                         y: center.y + sinA * radius))
                context.stroke(tick, with: .color(color.opacity(isMajor ? 0.5 : 0.22)),
                               lineWidth: isMajor ? 1.5 : 1)
            }

            // Base ring.
            let ringRect = CGRect(x: center.x - radius + 14, y: center.y - radius + 14,
                                  width: (radius - 14) * 2, height: (radius - 14) * 2)
            context.stroke(Path(ellipseIn: ringRect),
                           with: .color(color.opacity(0.18)), lineWidth: 3)

            // Progress / activity arc.
            let arcRadius = radius - 14
            var arc = Path()
            if let progress {
                arc.addArc(center: center, radius: arcRadius,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * progress.clamped(to: 0...1)),
                           clockwise: false)
            } else if active {
                let spin = t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
                arc.addArc(center: center, radius: arcRadius,
                           startAngle: .degrees(spin), endAngle: .degrees(spin + 100),
                           clockwise: false)
            }
            context.stroke(arc, with: .color(color.opacity(0.9 * pulse)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

/// Pulsing dot for the "running" state in lists and the menu bar.
struct PulsingDot: View {
    @Environment(\.hudStyle) private var style
    var active: Bool
    var color: Color? = nil

    var body: some View {
        let dotColor = color ?? (active ? style.palette.good : style.palette.textDim)
        return Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .shadow(color: dotColor.opacity(active ? 0.9 * style.glow : 0), radius: style.glowRadius(5))
            .overlay(
                Group {
                    if active && style.animationsEnabled {
                        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                            let t = timeline.date.timeIntervalSinceReferenceDate
                            let phase = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4
                            Circle()
                                .stroke(dotColor.opacity((1 - phase) * 0.7), lineWidth: 1.5)
                                .scaleEffect(1 + phase * 1.8)
                        }
                    }
                }
            )
            .accessibilityHidden(true)
    }
}
