import SwiftUI

/// Built-in visual themes.
enum HUDThemeID: String, Codable, CaseIterable, Identifiable {
    case neonCyan
    case electricBlue
    case electricViolet
    case plasmaMagenta
    case matrixGreen
    case solarOrange
    case minimalDark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neonCyan: return "Neon Cyan"
        case .electricBlue: return "Electric Blue"
        case .electricViolet: return "Electric Violet"
        case .plasmaMagenta: return "Plasma Magenta"
        case .matrixGreen: return "Matrix Green"
        case .solarOrange: return "Solar Orange"
        case .minimalDark: return "Minimal Dark"
        }
    }

    var palette: HUDPalette {
        switch self {
        case .neonCyan:
            return HUDPalette(accent: Color(red: 0.0, green: 0.92, blue: 1.0),
                              secondary: Color(red: 0.25, green: 0.55, blue: 1.0))
        case .electricBlue:
            return HUDPalette(accent: Color(red: 0.22, green: 0.6, blue: 1.0),
                              secondary: Color(red: 0.0, green: 0.9, blue: 1.0))
        case .electricViolet:
            return HUDPalette(accent: Color(red: 0.62, green: 0.44, blue: 1.0),
                              secondary: Color(red: 0.9, green: 0.35, blue: 1.0))
        case .plasmaMagenta:
            return HUDPalette(accent: Color(red: 1.0, green: 0.3, blue: 0.85),
                              secondary: Color(red: 0.62, green: 0.44, blue: 1.0))
        case .matrixGreen:
            return HUDPalette(accent: Color(red: 0.3, green: 1.0, blue: 0.55),
                              secondary: Color(red: 0.0, green: 0.85, blue: 0.75))
        case .solarOrange:
            return HUDPalette(accent: Color(red: 1.0, green: 0.62, blue: 0.2),
                              secondary: Color(red: 1.0, green: 0.85, blue: 0.35))
        case .minimalDark:
            return HUDPalette(accent: Color(white: 0.85),
                              secondary: Color(white: 0.6),
                              glowScale: 0.25)
        }
    }
}

/// Resolved colors + constants for the HUD look.
struct HUDPalette {
    var accent: Color
    var secondary: Color
    /// Extra damping for low-glow themes.
    var glowScale: Double = 1.0

    // Shared base colors — near-black background, deep navy/charcoal panels.
    let background = Color(red: 0.02, green: 0.03, blue: 0.05)
    let panel = Color(red: 0.05, green: 0.075, blue: 0.12)
    let panelHighlight = Color(red: 0.08, green: 0.115, blue: 0.18)
    let charcoal = Color(red: 0.09, green: 0.10, blue: 0.12)
    let textPrimary = Color(white: 0.92)
    let textSecondary = Color(white: 0.62)
    let textDim = Color(white: 0.4)
    let good = Color(red: 0.35, green: 0.95, blue: 0.55)
    let warning = Color(red: 1.0, green: 0.78, blue: 0.25)
    /// Red is reserved for errors, warnings and stop controls.
    let danger = Color(red: 1.0, green: 0.28, blue: 0.3)
}

/// Environment-style theme context assembled from settings + the selected
/// profile's accent override.
struct HUDStyle {
    var palette: HUDPalette
    /// 0…1 — from AppSettings.glowIntensity × palette.glowScale.
    var glow: Double
    /// 0…1 — animation intensity; 0 also when Reduce Motion is on.
    var motion: Double
    var showGrid: Bool
    var showScanlines: Bool
    var showParticles: Bool
    var compact: Bool

    var accent: Color { palette.accent }
    var secondary: Color { palette.secondary }

    /// Shadow radius helper honoring the glow setting.
    func glowRadius(_ base: CGFloat) -> CGFloat {
        base * CGFloat(glow)
    }

    var animationsEnabled: Bool { motion > 0.01 }

    static func make(settings: AppSettings, profileThemeID: String?, reduceMotion: Bool,
                     appActive: Bool = true) -> HUDStyle {
        let themeID = profileThemeID.flatMap(HUDThemeID.init(rawValue:))
            ?? HUDThemeID(rawValue: settings.themeID) ?? .neonCyan
        let palette = themeID.palette
        // When the app is not frontmost (e.g. the user switched to a game),
        // freeze all motion so the display-link-driven TimelineViews stop
        // and CPU use drops to ~0. The click engine is unaffected.
        let motion = (reduceMotion || !appActive) ? 0 : settings.animationIntensity
        return HUDStyle(
            palette: palette,
            glow: settings.glowIntensity * palette.glowScale,
            motion: motion,
            showGrid: settings.showGrid,
            showScanlines: settings.showScanlines && !reduceMotion && appActive,
            showParticles: settings.showParticles && !reduceMotion && appActive,
            compact: settings.compactLayout)
    }
}

private struct HUDStyleKey: EnvironmentKey {
    static let defaultValue = HUDStyle(
        palette: HUDThemeID.neonCyan.palette,
        glow: 0.7, motion: 0.8,
        showGrid: true, showScanlines: true, showParticles: true, compact: false)
}

extension EnvironmentValues {
    var hudStyle: HUDStyle {
        get { self[HUDStyleKey.self] }
        set { self[HUDStyleKey.self] = newValue }
    }
}
