//
//  AngleMath.swift
//  ThatWayCore
//
//  Compass-angle arithmetic that is correct across the 359°/0° wraparound. Every place that
//  compares, averages or animates bearings goes through here instead of re-deriving it.
//

import Foundation

public enum AngleMath {
    /// `degrees` normalised to 0..<360.
    public static func normalized(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }

    /// Signed turn from `b` to `a` in degrees, -180...180 (positive = clockwise).
    public static func signedDifference(_ a: Double, from b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d
    }

    /// Smallest angle between two bearings, 0...180.
    public static func difference(_ a: Double, _ b: Double) -> Double {
        abs(signedDifference(a, from: b))
    }

    /// Circular mean of bearings (nil for none), 0..<360.
    public static func circularMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let x = values.reduce(0.0) { $0 + cos($1 * .pi / 180) }
        let y = values.reduce(0.0) { $0 + sin($1 * .pi / 180) }
        return normalized(atan2(y, x) * 180 / .pi)
    }
}
