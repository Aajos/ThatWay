//
//  CompassModels.swift
//  ThatWay
//
//  Data ported from the "Compass Nav" design concept.
//

import SwiftUI

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
                 swatches: [Color(hex: "0B0907"), Color(hex: "FF5A36"), Color(hex: "F5F1EA")],
                 accent: Color(hex: "FF5A36"), ink: Color(hex: "F5F1EA"),
                 screen: Color(hex: "0B0907"), worldA: Color(hex: "2A211B"), worldB: Color(hex: "0A0807"),
                 dialA: Color(hex: "342216"), dialB: Color(hex: "0E0B09"),
                 glow: Color(hex: "080605"), needleRed: Color(hex: "FF3B2F"), needleGray: Color(hex: "7E7872"),
                 onAccent: .white),
        AppTheme(id: .tide, name: "Tide", note: "Deep water glass, mint markings.", light: false,
                 swatches: [Color(hex: "08131A"), Color(hex: "34D6A5"), Color(hex: "DCEFF5")],
                 accent: Color(hex: "34D6A5"), ink: Color(hex: "DBEEF6"),
                 screen: Color(hex: "08131A"), worldA: Color(hex: "134A63"), worldB: Color(hex: "060E14"),
                 dialA: Color(hex: "144058"), dialB: Color(hex: "060E14"),
                 glow: Color(hex: "040C12"), needleRed: Color(hex: "FF6B6B"), needleGray: Color(hex: "5C7F91"),
                 onAccent: Color(hex: "06231B")),
        AppTheme(id: .paper, name: "Paper", note: "Daylight. Printed dial, ink needle.", light: true,
                 swatches: [Color(hex: "F2EBDD"), Color(hex: "1D1A16"), Color(hex: "C2452C")],
                 accent: Color(hex: "C2452C"), ink: Color(hex: "1D1A16"),
                 screen: Color(hex: "F2EBDD"), worldA: Color(hex: "D3C3A6"), worldB: Color(hex: "EDE3D0"),
                 dialA: .white.opacity(0.55), dialB: Color(hex: "A39276").opacity(0.3),
                 glow: Color(hex: "FFFCF4"), needleRed: Color(hex: "C2452C"), needleGray: Color(hex: "9A9083"),
                 onAccent: .white),
        AppTheme(id: .arcade, name: "Arcade", note: "High contrast, loud glow.", light: false,
                 swatches: [Color(hex: "10031F"), Color(hex: "FF2E88"), Color(hex: "FFE347")],
                 accent: Color(hex: "FF2E88"), ink: Color(hex: "FFEBF7"),
                 screen: Color(hex: "10031F"), worldA: Color(hex: "4A0D6B"), worldB: Color(hex: "0A0116"),
                 dialA: Color(hex: "54106C"), dialB: Color(hex: "0C0218"),
                 glow: Color(hex: "0A0214"), needleRed: Color(hex: "FF2E88"), needleGray: Color(hex: "6A5AA8"),
                 onAccent: .white),
    ]

    static func byId(_ id: ThemeID) -> AppTheme { all.first { $0.id == id }! }
}

struct Friend: Identifiable {
    let id: String
    let name: String
    let initials: String
    let color: Color
    let mapPos: CGPoint // fraction 0...1 of the map's virtual 1200x1200 field

    static let all: [Friend] = [
        Friend(id: "ay", name: "Ayaan", initials: "AY", color: Color(hex: "FFB4A1"), mapPos: CGPoint(x: 760 / 1200, y: 380 / 1200)),
        Friend(id: "ri", name: "Riya", initials: "RI", color: Color(hex: "9FE8CE"), mapPos: CGPoint(x: 300 / 1200, y: 470 / 1200)),
        Friend(id: "de", name: "Dev", initials: "DE", color: Color(hex: "F5D98C"), mapPos: CGPoint(x: 840 / 1200, y: 700 / 1200)),
        Friend(id: "mi", name: "Mira", initials: "MI", color: Color(hex: "C7B8FF"), mapPos: CGPoint(x: 420 / 1200, y: 820 / 1200)),
        Friend(id: "ka", name: "Kabir", initials: "KA", color: Color(hex: "FF9E7A"), mapPos: CGPoint(x: 640 / 1200, y: 900 / 1200)),
    ]
}

enum TurnDir { case left, right, straight }
enum LaneSide: String { case any, leftish, left, rightish, right }

struct NavStep {
    let dir: TurnDir
    let dist: Double
    let copy: String
    let lane: String
    let side: LaneSide

    static let all: [NavStep] = [
        NavStep(dir: .left, dist: 420, copy: "Hang a left after the bakery", lane: "Keep to the left two lanes", side: .leftish),
        NavStep(dir: .straight, dist: 900, copy: "Straight on for a good while", lane: "You can relax here", side: .any),
        NavStep(dir: .right, dist: 260, copy: "Bear right at the fork", lane: "Get into the rightmost lane", side: .right),
        NavStep(dir: .left, dist: 180, copy: "Little left, then you're there", lane: "Far left lane, watch for cyclists", side: .left),
    ]
}

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
        case .compass: return "COMPASS"
        case .map: return "MAP"
        case .store: return "STORE"
        case .profile: return "YOU"
        }
    }
}

enum StoreTab: String, CaseIterable, Identifiable {
    case themes, skins, donate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .themes: return "Themes"
        case .skins: return "Skins"
        case .donate: return "Donate"
        }
    }
}

enum NavMode { case point, guidance }
enum DestKind { case place, friend }
enum Visibility: String, CaseIterable, Identifiable {
    case friends = "Friends", close = "Close ones", nobody = "Nobody"
    var id: String { rawValue }
}

struct NavOptions {
    var voice = "Friendly"
    var haptics = "Strong"
    var share = "Off"
    var units = "Kilometres"
    var activity = "Automatic"
}

/// Geometry helpers ported 1:1 from the design's math.
enum CompassGeometry {
    static let scalePoint: Double = 0.9
    static let scaleGuide: Double = 1.06
    static let laneIn: Double = 100
    static let laneOut: Double = 125
    static let r0: Double = 143

    static func laneDeg(for side: LaneSide) -> Double {
        let r = r0 * scaleGuide
        let inner = acos(laneIn / r) * 180 / .pi
        let outer = acos(laneOut / r) * 180 / .pi
        switch side {
        case .any: return 0
        case .leftish: return -outer
        case .left: return -inner
        case .rightish: return outer
        case .right: return inner
        }
    }

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
