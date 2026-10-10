//
//  CompassModels.swift
//  ThatWay
//
//  Data ported from the "Compass Nav" design concept.
//

import SwiftUI
import UIKit
import CoreLocation
import ThatWayCore
import ThatWayUI

extension Color {
    /// Relative luminance based readable ink color (near-black or near-white) for text on this fill.
    var onInk: Color {
        guard let comps = UIColor(self).cgColor.components, comps.count >= 3 else { return .white }
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let L = 0.2126 * lin(comps[0]) + 0.7152 * lin(comps[1]) + 0.0722 * lin(comps[2])
        return L > 0.32 ? Color(hex: "141110") : .white
    }

    func adjustedBrightness(_ delta: Double) -> Color {
        let c = hsba
        return Color(hue: c.h, saturation: c.s, brightness: max(0, min(1, c.b + delta)), opacity: c.a)
    }

    func hueShifted(_ degrees: Double) -> Color {
        let c = hsba
        var newHue = c.h + degrees / 360
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
