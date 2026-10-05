//
//  CompassModels.swift
//  ThatWay
//
//  Data ported from the "Compass Nav" design concept.
//

import SwiftUI
import UIKit
import CoreLocation

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: UInt64
        (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// Relative luminance based readable ink color (near-black or near-white) for text on this fill.
    var onInk: Color {
        guard let comps = UIColor(self).cgColor.components, comps.count >= 3 else { return .white }
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let L = 0.2126 * lin(comps[0]) + 0.7152 * lin(comps[1]) + 0.0722 * lin(comps[2])
        return L > 0.32 ? Color(hex: "141110") : .white
    }

    private var hsba: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b, a)
    }

    func adjustedBrightness(_ delta: Double) -> Color {
        let c = hsba
        return Color(hue: c.h, saturation: c.s, brightness: max(0, min(1, c.b + delta)), opacity: c.a)
    }

    func hueShifted(_ degrees: Double) -> Color {
        let c = hsba
        var newHue = c.h + CGFloat(degrees / 360)
        newHue = newHue.truncatingRemainder(dividingBy: 1)
        if newHue < 0 { newHue += 1 }
        return Color(hue: newHue, saturation: c.s, brightness: c.b, opacity: c.a)
    }

    /// 2-3 related tones derived from this color, standing in for "dominant colors pulled
    /// from the avatar" since our avatars are flat fills rather than real images.
    var dominantTrio: [Color] {
        [self, adjustedBrightness(0.16), hueShifted(-18).adjustedBrightness(-0.08)]
    }

    /// Linearly blends two colours in RGB space — used to fade the route line smoothly
    /// between activity colours instead of snapping at a threshold.
    static func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = max(0, min(1, t))
        func components(_ c: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let parts = UIColor(c).cgColor.components ?? [0, 0, 0, 1]
            if parts.count >= 4 { return (parts[0], parts[1], parts[2], parts[3]) }
            if parts.count == 2 { return (parts[0], parts[0], parts[0], parts[1]) }
            return (0, 0, 0, 1)
        }
        let (ar, ag, ab, aa) = components(a)
        let (br, bg, bb, ba) = components(b)
        return Color(
            red: Double(ar + (br - ar) * CGFloat(t)),
            green: Double(ag + (bg - ag) * CGFloat(t)),
            blue: Double(ab + (bb - ab) * CGFloat(t)),
            opacity: Double(aa + (ba - aa) * CGFloat(t))
        )
    }
}

enum ThemeID: String, CaseIterable, Identifiable {
    case ember, tide, paper, arcade
    var id: String { rawValue }
}

struct AppTheme: Identifiable {
    let id: ThemeID
    let name: String
    let note: String
    let light: Bool
    let swatches: [Color]
    let accent: Color
    let ink: Color
    /// Secondary/muted text — distinct from `ink.opacity()` so light mode gets its own
    /// proper grey rather than a washed-out tint of the dark ink color.
    let textSecondary: Color
    /// Hairline borders and inactive icon strokes.
    let borderColor: Color
    let screen: Color
    let worldA: Color
    let worldB: Color
    let dialA: Color
    let dialB: Color
    let glow: Color
    let needleRed: Color
    let needleGray: Color
    let onAccent: Color

    static let all: [AppTheme] = [
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

    static func byId(_ id: ThemeID) -> AppTheme { all.first { $0.id == id }! }

    // Travel-mode tile colours. Same hues in every theme (green on foot, blue driving, white
    // when stationary); light themes give the white "still" tile a visible border instead.
    var modeStill: Color { .white }
    var modeOnFoot: Color { Color(hex: "2FCF9B") }
    var modeDrive: Color { Color(hex: "3B82F6") }
    var modeStillBorder: Color { light ? borderColor : .white }

    func modeTint(_ mode: TravelMode, still: Bool = false) -> Color {
        if still { return modeStill }
        return mode.isOnFoot ? modeOnFoot : modeDrive
    }
}

/// A friend in the user's social roster — a real account, added via FriendsManager. Friends
/// still don't have a coordinate and don't appear on the map: there's no location-sharing
/// backend behind this yet, so tapping one can't point or route to them (that would mean
/// fabricating a location for a real person, which is exactly the kind of mock data this app
/// avoids elsewhere).
struct Friend: Identifiable, Codable, Equatable {
    let id: String
    let username: String
    /// "ACCEPTED" | "PENDING" | "INCOMING" — matches the backend's `Friends` table exactly.
    let status: String
    let requestedAt: String?
    let acceptedAt: String?

    var initials: String { String(username.prefix(2)).uppercased() }

    private static let palette: [Color] = [
        Color(hex: "FFB4A1"), Color(hex: "9FE8CE"), Color(hex: "F5D98C"),
        Color(hex: "C7B8FF"), Color(hex: "FF9E7A"), Color(hex: "8FD3FF"),
    ]

    /// Deterministic per-account color, standing in for a real avatar image.
    var color: Color {
        let index = abs(id.hashValue) % Self.palette.count
        return Self.palette[index]
    }
}

enum TurnDir { case left, right, straight }

enum SkinID: String, CaseIterable, Identifiable {
    case needle, wheel, clock, hand, vane, moon
    var id: String { rawValue }
}

struct Skin: Identifiable {
    let id: SkinID
    let name: String
    let glyph: String?
    let hasArt: Bool
    let price: Double

    static let all: [Skin] = [
        Skin(id: .needle, name: "Compass Needle", glyph: "⬟", hasArt: true, price: 0),
        Skin(id: .wheel, name: "Steering Wheel", glyph: "◎", hasArt: true, price: 0),
        Skin(id: .clock, name: "Clock Hands", glyph: "◔", hasArt: true, price: 0),
        Skin(id: .hand, name: "Pointing Hand", glyph: nil, hasArt: false, price: 3.99),
        Skin(id: .vane, name: "Weathervane", glyph: nil, hasArt: false, price: 2.99),
        Skin(id: .moon, name: "Moon Phase", glyph: nil, hasArt: false, price: 2.99),
    ]

    static func byId(_ id: SkinID) -> Skin { all.first { $0.id == id }! }
}

enum AvatarID: String, CaseIterable, Identifiable {
    case initials, dot, ring, astro, fox, van
    var id: String { rawValue }
}

struct AvatarOption: Identifiable {
    let id: AvatarID
    let name: String
    let glyph: String
    let bg: LinearGradient
    let price: Double

    static func solid(_ c: Color) -> LinearGradient {
        LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    static let all: [AvatarOption] = [
        AvatarOption(id: .initials, name: "Initials", glyph: "YO",
                     bg: LinearGradient(colors: [Color(hex: "FF5A36"), Color(hex: "34D6A5")], startPoint: .topLeading, endPoint: .bottomTrailing),
                     price: 0),
        AvatarOption(id: .dot, name: "Dot", glyph: "●", bg: solid(Color(hex: "F5D98C")), price: 0),
        AvatarOption(id: .ring, name: "Ring", glyph: "◎", bg: solid(Color(hex: "9FE8CE")), price: 0),
        AvatarOption(id: .astro, name: "Astronaut", glyph: "☽", bg: solid(Color(hex: "C7B8FF")), price: 2.99),
        AvatarOption(id: .fox, name: "Fox", glyph: "▲", bg: solid(Color(hex: "FFB4A1")), price: 2.99),
        AvatarOption(id: .van, name: "Retro Van", glyph: "▭", bg: solid(Color(hex: "8FD3FF")), price: 3.99),
    ]

    static func byId(_ id: AvatarID) -> AvatarOption { all.first { $0.id == id }! }
}

enum AppScreen: String, CaseIterable, Identifiable {
    case compass, map, store, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .compass: return "WAY"
        case .map: return "MAP"
        case .store: return "STORE"
        case .profile: return "YOU"
        }
    }

    var symbolName: String {
        switch self {
        // "compass.fill" isn't an actual SF Symbol; "safari.fill" is Apple's compass-rose glyph.
        case .compass: return "safari.fill"
        case .map: return "map.fill"
        case .store: return "bag.fill"
        case .profile: return "person.fill"
        }
    }
}

enum NavMode { case point, guidance }
enum DestKind { case none, place }
enum Visibility: String, CaseIterable, Identifiable {
    case friends = "Friends", close = "Close ones", nobody = "Nobody"
    var id: String { rawValue }
}

struct NavOptions {
    var voice = "Friendly"
    var haptics = "Strong"
    var share = "Off"
    var units = "Kilometres"
    var tilt = "Hard"
}

/// Geometry helpers ported 1:1 from the design's math.
enum CompassGeometry {
    static func fmt(_ metres: Double) -> String {
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
        }
        return "\(max(0, Int((metres / 10).rounded()) * 10)) m"
    }

    static func aud(_ n: Double) -> String {
        String(format: "$%.2f AUD", n)
    }
}

struct RecentPlace: Codable, Hashable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    /// The address (street / suburb) it resolved to — shown under the name, and what tells two
    /// same-named places (every "Coles") apart.
    var subtitle: String? = nil
    var id: String { "\(name)|\(String(format: "%.4f,%.4f", latitude, longitude))" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}


extension Color {
    /// The bright version of a colour for glowing on a light background: same hue, paler and at
    /// full brightness, so it blooms as light instead of reading as a darker smear of itself.
    func luminousGlow() -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * 0.5), brightness: 1, opacity: min(1, Double(a) * 1.5))
    }
}

extension AppTheme {
    /// An accent-coloured fill. Light themes need it stronger: the same 14% orange that reads on a
    /// dark screen is a washed-out pink on white.
    func tint(_ opacity: Double) -> Color {
        accent.opacity(light ? min(1, opacity * 1.9) : opacity)
    }

    /// An accent-coloured outline, bold on light themes.
    func outline(_ opacity: Double) -> Color {
        accent.opacity(light ? min(1, opacity * 2.4) : opacity)
    }

    /// The fill for cards and pills: translucent ink over a dark screen, solid white on a light one
    /// (ink at 5-7% over cream just reads as grey).
    func surface(_ darkOpacity: Double) -> Color {
        light ? Color.white.opacity(0.94) : ink.opacity(darkOpacity)
    }
}

extension View {
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
        if theme.light || !Perf.on("dialfx") {
            self
        } else {
            shadow(color: .black.opacity(darkOpacity), radius: radius, y: y)
        }
    }
}
