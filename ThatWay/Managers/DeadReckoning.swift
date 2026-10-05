//
//  DeadReckoning.swift
//  ThatWay
//
//  Between two GPS fixes the traveller keeps moving, but the last fix doesn't. Dead reckoning
//  estimates how far along the route they've got since that fix — last measured speed × time since
//  it — so the distance to the next turn counts down smoothly instead of jumping on each fix.
//
//  It is deliberately conservative, because standing still produces no fixes at all (the distance
//  filter only delivers a fix after real movement) and a stopped traveller must not be walked
//  down the road by the estimate:
//    - needs a usable speed, and a heading roughly along the route (not turning back, not off it);
//    - never more than a few seconds of travel, and never more than one distance-filter's worth of
//      metres — the most the traveller can have moved without CoreLocation delivering a new fix;
//    - never carries progress past the next manoeuvre or into the arrival radius (see
//      `RoutingManager.projectedProgress`), so cards and arrival only ever change on real fixes;
//    - every real fix replaces the estimate outright.
//
//  Pure, so it can be unit-tested without a phone.
//

import Foundation
import CoreLocation

enum DeadReckoning {
    /// Below this (m/s, ≈2.5 km/h) the speed reading is GPS noise on a stationary phone.
    static let minimumSpeed: CLLocationSpeed = 0.7
    /// Longest stretch of travel the estimate will cover without a fresh fix.
    static let maximumAge: TimeInterval = 6
    /// A course more than this far from the route's direction means they're not following it.
    static let maximumCourseError: CLLocationDirection = 60

    /// Metres to add to the last fix's progress along the route.
    /// - Parameters:
    ///   - speed: the fix's speed (m/s); negative when the system couldn't measure one.
    ///   - course: the fix's direction of travel in degrees, negative when unknown.
    ///   - routeBearing: direction of the route segment the fix is on, if known.
    ///   - age: seconds since the fix was taken.
    ///   - distanceCap: the active distance filter — the most they can have moved unseen.
    static func extraMetres(
        speed: CLLocationSpeed,
        course: CLLocationDirection,
        routeBearing: CLLocationDirection?,
        age: TimeInterval,
        distanceCap: CLLocationDistance
    ) -> Double {
        guard speed >= minimumSpeed, age > 0, distanceCap > 0 else { return 0 }
        if course >= 0, let routeBearing, angularDifference(course, routeBearing) > maximumCourseError { return 0 }
        return min(speed * min(age, maximumAge), distanceCap)
    }

    /// Smallest angle between two bearings, 0...180.
    static func angularDifference(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        return abs(d > 180 ? d - 360 : d < -180 ? d + 360 : d)
    }
}
