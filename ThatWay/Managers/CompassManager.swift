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

    /// Walks `distance` metres along a polyline (a sequence of connected segments) from
    /// its start, returning the interpolated point that far along — used to move a
    /// simulated traveller smoothly along real route geometry rather than cutting corners
    /// straight toward the next waypoint. Clamps to the last point once `distance` exceeds
    /// the polyline's total length.
    static func pointAlong(_ polyline: [CLLocationCoordinate2D], distance: CLLocationDistance) -> CLLocationCoordinate2D? {
        guard let first = polyline.first else { return nil }
        guard polyline.count > 1 else { return first }
        var remaining = max(0, distance)
        for i in 0..<(polyline.count - 1) {
            let segmentStart = polyline[i]
            let segmentEnd = polyline[i + 1]
            let segmentLength = Self.distance(from: segmentStart, to: segmentEnd)
            if remaining <= segmentLength {
                guard segmentLength > 0 else { return segmentStart }
                let fraction = remaining / segmentLength
                return CLLocationCoordinate2D(
                    latitude: segmentStart.latitude + (segmentEnd.latitude - segmentStart.latitude) * fraction,
                    longitude: segmentStart.longitude + (segmentEnd.longitude - segmentStart.longitude) * fraction
                )
            }
            remaining -= segmentLength
        }
        return polyline.last
    }

    /// The closest point on a polyline to `location`, together with how far away it is and
    /// which segment it falls on. Used to trim a route line down to "what's left ahead" as
    /// the traveller moves, and to detect drifting off the planned route entirely.
    struct NearestPointResult {
        let point: CLLocationCoordinate2D
        let distance: CLLocationDistance
        /// Index of the segment's start point — the remaining path continues from
        /// `polyline[segmentIndex + 1]` onward.
        let segmentIndex: Int
    }

    static func nearestPoint(on polyline: [CLLocationCoordinate2D], to location: CLLocationCoordinate2D) -> NearestPointResult? {
        guard let first = polyline.first else { return nil }
        guard polyline.count > 1 else {
            return NearestPointResult(point: first, distance: distance(from: location, to: first), segmentIndex: 0)
        }
        var best: NearestPointResult?
        for i in 0..<(polyline.count - 1) {
            let projected = projectPoint(location, ontoSegmentFrom: polyline[i], to: polyline[i + 1])
            let d = distance(from: location, to: projected)
            if best == nil || d < best!.distance {
                best = NearestPointResult(point: projected, distance: d, segmentIndex: i)
            }
        }
        return best
    }

    /// Projects `point` onto the segment from `a` to `b` (clamped to the segment), using a
    /// local flat-earth approximation — accurate enough at the scale of one route segment —
    /// then converts back to a real coordinate.
    private static func projectPoint(_ point: CLLocationCoordinate2D, ontoSegmentFrom a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(a.latitude.radians)
        let bx = (b.longitude - a.longitude) * metersPerDegreeLon
        let by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (point.longitude - a.longitude) * metersPerDegreeLon
        let py = (point.latitude - a.latitude) * metersPerDegreeLat
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? max(0, min(1, (px * bx + py * by) / lengthSquared)) : 0
        return CLLocationCoordinate2D(
            latitude: a.latitude + (by * t) / metersPerDegreeLat,
            longitude: a.longitude + (bx * t) / metersPerDegreeLon
        )
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
