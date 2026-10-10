//
//  RouteTracker.swift
//  ThatWayCore
//
//  Where along a route the traveller is, and what's next — the pure, UI-free core of route progress
//  (the iOS app's `RoutingManager` carries the same maths wrapped in fetching and published state;
//  folding it onto this is a follow-up). Windowed nearest-point search so a road that loops back near
//  itself can't yank progress to the wrong stretch; progress never goes backward.
//

import Foundation
import CoreLocation

public struct RouteTracker {
    public struct Progress: Equatable {
        public var along: Double
        public var remaining: Double
        /// The next manoeuvre ahead (never the departure), nil once only the arrival is left.
        public var nextTurn: TurnShape?
        public var nextStepIndex: Int?
        /// Metres along the route to that manoeuvre (or to the arrival when it's the last).
        public var distanceToNext: Double
        /// True-north bearing from the traveller to the next waypoint.
        public var bearingToNext: Double
        public var offRoute: Bool
        public var arrived: Bool

        public static func == (a: Progress, b: Progress) -> Bool {
            a.along == b.along && a.nextStepIndex == b.nextStepIndex && a.offRoute == b.offRoute && a.arrived == b.arrived
        }
    }

    public let route: Route
    public private(set) var along: Double = 0
    private let cumulative: [Double]
    private var lastSegment = 0
    public var corridor: Double
    public var arrivalRadius: Double

    public init(route: Route, mode: TravelMode = .walk) {
        self.route = route
        self.corridor = mode.tuning.corridorRadius
        self.arrivalRadius = mode.tuning.arrivalRadius
        var cum = [0.0]
        for i in route.geometry.indices.dropFirst() {
            cum.append(cum[i - 1] + CompassManager.distance(from: route.geometry[i - 1], to: route.geometry[i]))
        }
        cumulative = cum
    }

    public var length: Double { cumulative.last ?? 0 }

    public mutating func update(position: CLLocationCoordinate2D) -> Progress {
        let geometry = route.geometry
        var distanceOff = 0.0
        if geometry.count > 1 {
            let last = geometry.count - 2
            let low = max(0, min(last, lastSegment - 3))
            let high = min(last, lastSegment + 120)
            var best = CompassManager.nearestPoint(on: Array(geometry[low...(high + 1)]), to: position)
            var segment = low + (best?.segmentIndex ?? 0)
            if best == nil || best!.distance > 60, let global = CompassManager.nearestPoint(on: geometry, to: position),
               best == nil || global.distance < best!.distance {
                best = global; segment = global.segmentIndex
            }
            if let best, best.distance < 150 {
                lastSegment = segment
                let a = cumulative[segment] + CompassManager.distance(from: geometry[segment], to: best.point)
                if a > along { along = a }
            }
            distanceOff = best?.distance ?? 0
        }

        let remaining = max(0, length - along)
        // The next *instruction*: skip the departure and pass-through steps ("new name", "continue") that don't turn,
        // so the arrow and distance always refer to something the wearer actually has to do. Roundabouts and the
        // arrival always count.
        let next = route.steps.enumerated().first { _, step in
            guard step.startAlong > along + 1, step.maneuverType != "depart" else { return false }
            let alwaysCounts = ["arrive", "roundabout", "rotary"].contains(step.maneuverType)
            return alwaysCounts || step.turn.side != .straight
        }
        let target = next.map { $0.element.startCoordinate } ?? geometry.last ?? position
        return Progress(
            along: along, remaining: remaining,
            nextTurn: next.flatMap { $0.element.maneuverType == "arrive" ? nil : $0.element.turn },
            nextStepIndex: next?.offset,
            distanceToNext: next.map { max(0, $0.element.startAlong - along) } ?? remaining,
            bearingToNext: CompassManager.bearing(from: position, to: target),
            offRoute: distanceOff > corridor,
            arrived: remaining <= arrivalRadius
        )
    }
}
