import SwiftUI

struct AboutView: View {
    @Environment(\.hudStyle) private var style

    var body: some View {
        HUDScreen(title: "About") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 34))
                        .foregroundStyle(style.accent)
                        .shadow(color: style.accent.opacity(0.7 * style.glow), radius: style.glowRadius(10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUTOCLICKER")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(style.palette.textPrimary)
                        Text("Version 1.0 — native Swift / SwiftUI for macOS 13+")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(style.palette.textSecondary)
                    }
                }
                Text("A configurable automatic clicking utility with global mouse-button and keyboard triggers, humanized timing, coordinate targeting, sequences and profiles.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(style.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .hudPanel()

            VStack(alignment: .leading, spacing: 8) {
                HUDSectionHeader(title: "Intended Use", systemImage: "hand.raised")
                Text("Built for accessibility assistance, interface testing, repetitive-task relief and controlled local automation. Humanized timing exists to feel comfortable and avoid mechanical hammering of your own machine — not to bypass anti-bot systems, application safeguards, rate limits or platform rules. Respect the terms of the software you automate.")
                    .font(.system(size: 11))
                    .foregroundStyle(style.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .hudPanel()

            VStack(alignment: .leading, spacing: 8) {
                HUDSectionHeader(title: "Technology", systemImage: "cpu")
                ForEach([
                    "SwiftUI interface with an AppKit/CoreGraphics input core",
                    "CGEventTap global monitoring on a dedicated thread",
                    "CGEvent click synthesis, tagged to prevent self-triggering",
                    "Truncated-normal humanized interval generation with drift correction",
                    "JSON profile persistence in Application Support",
                ], id: \.self) { line in
                    Label(line, systemImage: "chevron.right")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(style.palette.textDim)
                }
            }
            .hudPanel()
        }
    }
}
