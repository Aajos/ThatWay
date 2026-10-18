//
//  SyntheticRoute.swift
//  ThatWayCore
//
//  Builds a simple test route *relative to wherever the traveller is standing* — straight legs with
//  turns between them — so a spike or a demo needs no stored coordinates and no network. The route has
//  real `Route`/`RouteStep` shape, so everything downstream (progress, next-waypoint distance, arrows)
//  runs on the same code as a real route.
//

import Foundation
import CoreLocation

public enum SyntheticRoute {
    public struct Leg {
        public var metres: Double
        /// The turn at the END of this leg (nil for the last leg, which ends at the destination).
        public var turn: TurnSide?
        public init(metres: Double, turn: TurnSide? = nil) { self.metres = metres; self.turn = turn }
    }

    /// The point `distance` metres from `origin` along `bearing` (flat-earth: fine at a few hundred metres).
    public static func offset(_ origin: CLLocationCoordinate2D, bearing: Double, metres: Double) -> CLLocationCoordinate2D {
        let rad = bearing * .pi / 180
        let dLat = metres * cos(rad) / 111_320
        let dLon = metres * sin(rad) / (111_320 * cos(origin.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: origin.latitude + dLat, longitude: origin.longitude + dLon)
    }

    public static func make(from start: CLLocationCoordinate2D, initialBearing: Double, legs: [Leg]) -> Route {
        var geometry = [start]
        var steps: [RouteStep] = []
        var along = 0.0
        var bearing = initialBearing
        var cursor = start

        func step(_ type: String, _ modifier: String?, at point: CLLocationCoordinate2D, along: Double, index: Int, turn: TurnShape, bearing: Double, instruction: String) -> RouteStep {
            RouteStep(id: UUID(), instruction: instruction, distance: 0, duration: 0, name: "", maneuverType: type, maneuverModifier: modifier,
                      startCoordinate: point, endCoordinate: point, bearing: bearing, intersections: [], startAlong: along, endAlong: along,
                      startIndex: index, endIndex: index, turn: turn, exitNumber: nil, exitBearing: bearing)
        }
        steps.append(step("depart", nil, at: start, along: 0, index: 0, turn: .straight, bearing: bearing, instruction: "Head out"))

        for (i, leg) in legs.enumerated() {
            // Points every 20 m so progress tracking behaves like a real, finely-sampled route.
            let count = max(1, Int((leg.metres / 20).rounded()))
            for k in 1...count {
                geometry.append(offset(cursor, bearing: bearing, metres: leg.metres * Double(k) / Double(count)))
            }
            cursor = offset(cursor, bearing: bearing, metres: leg.metres)
            along += leg.metres
            let index = geometry.count - 1
            if let turn = leg.turn, i < legs.count - 1 {
                let shape = TurnShape(side: turn, severity: .normal)
                steps.append(step("turn", turn == .left ? "left" : "right", at: cursor, along: along, index: index, turn: shape, bearing: bearing,
                                  instruction: "Turn \(turn == .left ? "left" : "right")"))
                bearing = AngleMath.normalized(bearing + (turn == .left ? -90 : 90))
            }
        }
        steps.append(step("arrive", nil, at: cursor, along: along, index: geometry.count - 1, turn: .straight, bearing: bearing, instruction: "Arrive"))
        return Route(geometry: geometry, distance: along, duration: along / 1.4, steps: steps, segmentDurations: [], segmentSpeeds: [])
    }
}
