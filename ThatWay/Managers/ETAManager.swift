//
//  ETAManager.swift
//  ThatWay
//
//  Estimates when the traveller will arrive. The baseline is OSRM's own road data — how long each
//  polyline segment takes at its road's profile speed (road class and speed limits; OSRM's demo
//  server has no live traffic) — from where they are now to the end. That's then scaled by how the
//  traveller is actually moving compared with those road speeds, smoothed so a red light or a
//  brief burst of speed doesn't make the time jump around.
//

import Foundation
import Combine

@MainActor
final class ETAManager: ObservableObject {
    // Plain properties, not @Published: nothing observes this object (the compass screen re-reads
    // it whenever AppModel republishes), so a publisher here only cost two Combine sends a second.
    private(set) var remainingSeconds: TimeInterval?
    private(set) var arrival: Date?

    /// Actual pace ÷ expected pace, smoothed: 1 = on the road's expected speed, >1 = slower.
    private var paceFactor = 1.0

    private static let walkingSpeed = 1.4 // m/s, when OSRM's driving data doesn't apply

    func reset() {
        remainingSeconds = nil
        arrival = nil
        paceFactor = 1
    }

    func update(routing: RoutingManager, speedKmh: Double, activity: TravelMode) {
        guard routing.hasRoute, routing.routeLength > 0 else { reset(); return }
        let remainingDistance = routing.remainingDistance
        let useRoadData = activity == .drive && !routing.segmentDurations.isEmpty
        let segment = min(routing.currentSegment, max(0, routing.segmentDurations.count - 1))

        // What the road says it takes from here to the end.
        var baseline: TimeInterval
        var expectedSpeed: Double
        if useRoadData {
            baseline = routing.segmentDurations.suffix(from: min(segment + 1, routing.segmentDurations.count)).reduce(0, +)
            baseline += routing.segmentDurations[segment] * 0.5 // half of the segment they're in
            expectedSpeed = routing.segmentSpeeds.indices.contains(segment) ? routing.segmentSpeeds[segment] : 13
        } else {
            baseline = remainingDistance / Self.walkingSpeed
            expectedSpeed = Self.walkingSpeed
        }

        // Only learn the pace while actually moving.
        let actual = speedKmh / 3.6
        if actual > 1.5, expectedSpeed > 0.5 {
            let ratio = max(0.5, min(2.5, expectedSpeed / actual))
            paceFactor = paceFactor * 0.97 + ratio * 0.03
        }
        let factor = max(0.7, min(1.8, paceFactor))
        let seconds = max(0, baseline * factor)
        remainingSeconds = seconds
        arrival = Date().addingTimeInterval(seconds)
    }

    // Creating a DateFormatter is expensive and this is read several times per redraw.
    private static let clockFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()
    private static let periodFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "a"; return f }()

    /// "3:42" and "PM" — split so the AM/PM can be set small next to the time.
    var arrivalClock: (time: String, period: String)? {
        guard let arrival else { return nil }
        return (Self.clockFormatter.string(from: arrival), Self.periodFormatter.string(from: arrival).lowercased())
    }

    var minutesLeftText: String? {
        guard let remainingSeconds else { return nil }
        let minutes = Int((remainingSeconds / 60).rounded(.up))
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
