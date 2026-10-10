//
//  LocationProfile.swift
//  ThatWay
//
//  How hard to ask CoreLocation to work right now. Pure, so it can be tested without a phone:
//  the answer depends only on what the app is doing, the travel mode and how far the next turn is.
//
//  Guiding: coarse-ish GPS (10 m) with a wide distance filter while the next turn is far away,
//  full accuracy with a tight filter once inside the mode's `precisionRadius`. Standing still
//  drops to low-accuracy updates, which iOS can serve without keeping the GPS chip hot; the first
//  real movement brings full accuracy straight back. Point mode and idle never need better than
//  10 m / 100 m.
//

import Foundation
import CoreLocation
import ThatWayCore

struct LocationProfile: Equatable {
    var accuracy: CLLocationAccuracy
    var distanceFilter: CLLocationDistance
    var headingFilter: CLLocationDegrees

    /// No fix for this long while guiding counts as standing still.
    static let stationaryAfter: TimeInterval = 20

    static func make(
        mode: TravelMode,
        guiding: Bool,
        hasDestination: Bool,
        distanceToNextTurn: Double?,
        stationary: Bool,
        lowPower: Bool
    ) -> LocationProfile {
        let tuning = mode.tuning
        var accuracy: CLLocationAccuracy
        var filter: CLLocationDistance
        var heading: CLLocationDegrees

        if guiding {
            let near = distanceToNextTurn.map { $0 <= tuning.precisionRadius } ?? false
            accuracy = near ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
            filter = near ? tuning.nearDistanceFilter : tuning.farDistanceFilter
            heading = 3
        } else if hasDestination {
            accuracy = kCLLocationAccuracyNearestTenMeters
            filter = 10
            heading = 2
        } else {
            accuracy = kCLLocationAccuracyHundredMeters
            filter = 25
            heading = 2
        }

        if stationary {
            accuracy = kCLLocationAccuracyHundredMeters
            filter = max(filter, 25)
        }
        if lowPower {
            filter *= 1.5
            heading += 2
            if accuracy == kCLLocationAccuracyBest { accuracy = kCLLocationAccuracyNearestTenMeters }
        }
        return LocationProfile(accuracy: accuracy, distanceFilter: filter, headingFilter: heading)
    }
}
