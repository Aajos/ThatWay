//
//  AppTheme.swift
//  ThatWayUI
//
//  The theme palettes (Ember, Tide, Paper, Arcade) and the helpers that make them look right on both
//  dark and light screens. Shared by the iPhone app and the watch app.
//

import SwiftUI
import ThatWayCore

public enum ThemeID: String, CaseIterable, Identifiable {
    case ember, tide, paper, arcade
    public var id: String { rawValue }
}

public struct AppTheme: Identifiable {
    public let id: ThemeID
    public let name: String
    public let note: String
    public let light: Bool
    public let swatches: [Color]
    public let accent: Color
    public let ink: Color
    /// Secondary/muted text — distinct from `ink.opacity()` so light mode gets its own
    /// proper grey rather than a washed-out tint of the dark ink color.
    public let textSecondary: Color
    /// Hairline borders and inactive icon strokes.
    public let borderColor: Color
    public let screen: Color
    public let worldA: Color
    public let worldB: Color
    public let dialA: Color
    public let dialB: Color
    public let glow: Color
    public let needleRed: Color
    public let needleGray: Color
    public let onAccent: Color

    public static let all: [AppTheme] = [
        AppTheme(id: .ember, name: "Ember", note: "Warm black, coral needle. The default.", light: false,
                 swatches: [Color(hex: "0A0A0A"), Color(hex: "FF5A36"), Color(hex: "FFFFFF")],
                 accent: Color(hex: "FF5A36"), ink: Color(hex: "FFFFFF"),
                 textSecondary: Color(hex: "B0B0B0"), borderColor: .white.opacity(0.14),
                 screen: Color(hex: "0A0A0A"), worldA: Color(hex: "2A211B"), worldB: Color(hex: "0A0807"),
                 dialA: Color(hex: "342216"), dialB: Color(hex: "0E0B09"),
                 glow: Color(hex: "080605"), needleRed: Color(hex: "FF3B2F"), needleGray: Color(hex: "7E7872"),
                 onAccent: .white),
        AppTheme(id: .tide, name: "Tide", note: "Deep water glass, mint markings.", light: false,
                 swatches: [Color(hex: "08131A"), Color(hex: "34D6A5"), Color(hex: "DCEFF5")],
                 accent: Color(hex: "34D6A5"), ink: Color(hex: "DBEEF6"),
                 textSecondary: Color(hex: "8CA6B0"), borderColor: .white.opacity(0.14),
                 screen: Color(hex: "08131A"), worldA: Color(hex: "134A63"), worldB: Color(hex: "060E14"),
                 dialA: Color(hex: "144058"), dialB: Color(hex: "060E14"),
                 glow: Color(hex: "040C12"), needleRed: Color(hex: "FF6B6B"), needleGray: Color(hex: "5C7F91"),
                 onAccent: Color(hex: "06231B")),
        AppTheme(id: .paper, name: "Paper", note: "Daylight. Warm cream, vivid orange.", light: true,
                 swatches: [Color(hex: "F8F5F1"), Color(hex: "0E0C0A"), Color(hex: "FF7A1F")],
                 accent: Color(hex: "FF7A1F"), ink: Color(hex: "0E0C0A"),
                 textSecondary: Color(hex: "6B625A"), borderColor: Color(hex: "3B332C"),
                 screen: Color(hex: "F8F5F1"), worldA: Color(hex: "E3D9C8"), worldB: Color(hex: "EFE9DE"),
                 dialA: Color(hex: "FFFFFF"), dialB: Color(hex: "ECE7DF"),
                 glow: Color(hex: "FFFCF4"), needleRed: Color(hex: "FF2D1F"), needleGray: Color(hex: "9A9083"),
                 onAccent: .white),
        AppTheme(id: .arcade, name: "Arcade", note: "High contrast, loud glow.", light: false,
                 swatches: [Color(hex: "10031F"), Color(hex: "FF2E88"), Color(hex: "FFE347")],
                 accent: Color(hex: "FF2E88"), ink: Color(hex: "FFEBF7"),
                 textSecondary: Color(hex: "B8A8C8"), borderColor: .white.opacity(0.16),
                 screen: Color(hex: "10031F"), worldA: Color(hex: "4A0D6B"), worldB: Color(hex: "0A0116"),
                 dialA: Color(hex: "54106C"), dialB: Color(hex: "0C0218"),
                 glow: Color(hex: "0A0214"), needleRed: Color(hex: "FF2E88"), needleGray: Color(hex: "6A5AA8"),
                 onAccent: .white),
    ]

    public static func byId(_ id: ThemeID) -> AppTheme { all.first { $0.id == id }! }

    // Travel-mode tile colours. Same hues in every theme (green on foot, blue driving, white
    // when stationary); light themes give the white "still" tile a visible border instead.
    public var modeStill: Color { .white }
    public var modeOnFoot: Color { Color(hex: "2FCF9B") }
    public var modeDrive: Color { Color(hex: "3B82F6") }
    public var modeStillBorder: Color { light ? borderColor : .white }

    public func modeTint(_ mode: TravelMode, still: Bool = false) -> Color {
        if still { return modeStill }
        return mode.isOnFoot ? modeOnFoot : modeDrive
    }

    /// An accent-coloured fill. Light themes need it stronger: the same 14% orange that reads on a
    /// dark screen is a washed-out pink on white.
    public func tint(_ opacity: Double) -> Color {
        accent.opacity(light ? min(1, opacity * 1.9) : opacity)
    }

    /// An accent-coloured outline, bold on light themes.
    public func outline(_ opacity: Double) -> Color {
        accent.opacity(light ? min(1, opacity * 2.4) : opacity)
    }

    /// The fill for cards and pills: translucent ink over a dark screen, solid white on a light one
    /// (ink at 5-7% over cream just reads as grey).
    public func surface(_ darkOpacity: Double) -> Color {
        light ? Color.white.opacity(0.94) : ink.opacity(darkOpacity)
    }
}

/// Switches the host app can use to turn effects off (the iPhone app's performance harness does).
public enum ThemeEffects {
    public static var liftEnabled: () -> Bool = { true }
}

public extension View {
    /// A halo around something that should pop. Dark themes bloom in the element's own colour; light
    /// themes bloom in a brighter, paler version of it, never a darker one.
    @ViewBuilder
    func glow(_ color: Color, radius: CGFloat, theme: AppTheme) -> some View {
        if theme.light {
            shadow(color: color.luminousGlow(), radius: radius * 1.5)
        } else {
            shadow(color: color, radius: radius)
        }
    }

    /// The soft lift under a panel: a dark shadow on dark themes, nothing dark on light ones.
    @ViewBuilder
    func lift(theme: AppTheme, radius: CGFloat, y: CGFloat = 0, darkOpacity: Double = 0.45) -> some View {
        if theme.light || !ThemeEffects.liftEnabled() {
            self
        } else {
            shadow(color: .black.opacity(darkOpacity), radius: radius, y: y)
        }
    }
}
