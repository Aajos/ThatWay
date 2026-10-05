//
//  ContinuousAngle.swift
//  ThatWay
//
//  Compass angles arrive wrapped (-180...180 or 0...360). Animating a *wrapped* angle makes the
//  dial spin the long way round whenever the value crosses the wrap point — at one specific
//  direction the needle and ring would whirl 360° instead of moving a degree. A ContinuousAngle
//  keeps an unbounded running value that always moves by the shortest turn, so an animation
//  between two readings never goes the long way.
//

import Foundation

struct ContinuousAngle: Equatable {
    private(set) var value: Double

    init(_ wrapped: Double = 0) { value = wrapped }

    /// Moves to `wrapped` by the shortest turn. Idempotent: updating with the same reading again
    /// leaves the value where it is.
    mutating func update(to wrapped: Double) {
        value += CompassHealth.signedDifference(wrapped, from: value)
    }
}
