//
//  CompassManager.swift
//  ThatWay
//
//  Pure coordinate math: bearing and distance between two points, and the
//  needle math for pointing a compass at a target while the device turns.
//

import CoreLocation

enum DistanceUnit {
    case metric, imperial
}

enum CompassManager {
    /// Initial great-circle bearing from `origin` to `destination`, in degrees
    /// clockwise from true north, normalized to [0, 360).
    static func bearing(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = origin.latitude.radians
        let lon1 = origin.longitude.radians
        let lat2 = destination.latitude.radians
        let lon2 = destination.longitude.radians

        let deltaLon = lon2 - lon1
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearingRadians = atan2(y, x)
        let bearingDegrees = bearingRadians.degrees
        return (bearingDegrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Great-circle distance between two coordinates, in metres.
    static func distance(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    /// The angle to rotate a needle, relative to the top of the screen, so it points
    /// at `bearing` while the device is currently facing `heading`. Normalized to (-180, 180].
    static func relativeBearing(heading: CLLocationDirection, bearing: CLLocationDirection) -> Double {
        var delta = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if delta <= -180 { delta += 360 }
        if delta > 180 { delta -= 360 }
        return delta
    }

    /// A short compass-point label (N, NE, E, ...) for a heading/bearing in degrees.
    static func compassPoint(for degrees: CLLocationDirection) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % points.count
        return points[index]
    }

    static func formattedDistance(_ metres: CLLocationDistance, unit: DistanceUnit = .metric) -> String {
        switch unit {
        case .metric:
            return metres >= 1000
                ? String(format: "%.1f km", metres / 1000)
                : "\(max(0, Int(metres.rounded()))) m"
        case .imperial:
            let feet = metres * 3.28084
            let miles = feet / 5280
            return miles >= 0.1
                ? String(format: "%.1f mi", miles)
                : "\(max(0, Int(feet.rounded()))) ft"
        }
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
