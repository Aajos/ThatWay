//
//  ColorTools.swift
//  ThatWayUI
//
//  Colour helpers that work on iPhone and Apple Watch alike (no UIColor: components are read through
//  `Color.resolve`, which exists everywhere SwiftUI does).
//

import SwiftUI

public extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: UInt64
        (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// Hue, saturation, brightness and alpha (each 0...1) of this colour.
    var hsba: (h: Double, s: Double, b: Double, a: Double) {
        let c = resolve(in: EnvironmentValues())
        let r = Double(c.red), g = Double(c.green), b = Double(c.blue)
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC, Double(c.opacity))
    }

    /// The bright version of a colour for glowing on a light background: same hue, paler and at
    /// full brightness, so it blooms as light instead of reading as a darker smear of itself.
    func luminousGlow() -> Color {
        let c = hsba
        return Color(hue: c.h, saturation: min(1, c.s * 0.5), brightness: 1, opacity: min(1, c.a * 1.5))
    }
}
