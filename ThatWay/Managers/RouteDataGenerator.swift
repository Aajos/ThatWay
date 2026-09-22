//
//  RouteDataGenerator.swift
//  ThatWay
//
//  Bakes a fetched OSRM route into dense, pre-computed guidance data once, off the main
//  actor, so guidance mode can cheaply answer "how far off the road am I, and how far to
//  the next turn" every tick by looking up the nearest baked waypoint instead of re-walking
//  the raw polyline and step list each time. Pure computation only — no UI here.
//

import Foundation
import CoreLocation
import Combine

/// The two tolerance profiles guidance data is baked for — a driver can reasonably drift
/// further from the route's line (lane width, GPS noise at speed) than someone on foot.
enum GuidanceActivity: String, Codable {
    case walking
    case driving

    /// Perpendicular offset tolerance, in metres: 15m walking, 30m driving.
    var corridorRadius: CLLocationDistance { self == .driving ? 30 : 15 }
}

/// One pre-computed sample point along the route, roughly every 10-20m of ground covered.
struct GuidanceWaypoint: Codable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// How far along the route (metres) this waypoint sits, measured from the route's start.
    let distanceFromStart: CLLocationDistance
    /// Direction of travel at this waypoint, degrees clockwise from true north.
    let bearing: CLLocationDirection
    /// How far ahead (metres) the next turn/maneuver is, from this waypoint.
    let distanceToNextTurn: CLLocationDistance
    /// The "visual corridor" radius at this waypoint — a circle of this radius centred on
    /// the waypoint is the tolerance band a traveller can wander within before counting as
    /// off-route.
    let corridorRadius: CLLocationDistance

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    /// The waypoint's corridor as a plain (center, radius) pair — callers draw or test
    /// against this however they like; this manager doesn't render anything itself.
    var corridorCircle: (center: CLLocationCoordinate2D, radius: CLLocationDistance) { (coordinate, corridorRadius) }
}

/// The baked result for one route: every sampled waypoint, plus the metadata it was baked
/// under. Codable end to end so it can be persisted or shipped elsewhere if ever needed,
/// even though the normal lifecycle here just keeps it in memory for one guidance session.
struct GuidanceData: Codable {
    let waypoints: [GuidanceWaypoint]
    let totalDistance: CLLocationDistance
    let activity: GuidanceActivity
    let generatedAt: Date
}

/// Pre-computes and caches `GuidanceData` for the active route. Nothing here touches the
/// UI — it just bakes data once when guidance starts (or a reroute invalidates it) and
/// holds onto it until guidance ends, so everything else can read pre-computed answers
/// instead of recomputing route geometry on every tick.
@MainActor
final class RouteDataGenerator: ObservableObject {
    @Published private(set) var guidanceData: GuidanceData?
    @Published private(set) var isGenerating = false

    private var bakeTask: Task<Void, Never>?
    /// How far apart (metres) baked waypoints are sampled — within the requested 10-20m band.
    private let sampleInterval: CLLocationDistance = 15

    /// Generates guidance data for `polyline`/`steps`, unless data already exists — in which
    /// case it's reused as-is. Called once, when the traveller comes within 500m of the destination — only that final stretch is ever baked.
    func generateGuidanceData(polyline: [CLLocationCoordinate2D], steps: [RouteStep], activity: GuidanceActivity) {
        guard guidanceData == nil else {
            print("[RouteDataGenerator] Reusing existing guidance data (\(guidanceData?.waypoints.count ?? 0) waypoints)")
            return
        }
        bake(polyline: polyline, steps: steps, activity: activity)
    }

    /// Drops the cached data and cancels any in-flight bake — call this when guidance ends
    /// or the destination is reached, so stale waypoints never leak into the next route.
    func clearGuidanceData() {
        bakeTask?.cancel()
        bakeTask = nil
        guidanceData = nil
        isGenerating = false
    }

    private func bake(polyline: [CLLocationCoordinate2D], steps: [RouteStep], activity: GuidanceActivity) {
        bakeTask?.cancel()
        guard polyline.count > 1 else { return }
        isGenerating = true
        let interval = sampleInterval
        print("[RouteDataGenerator] Baking guidance data: \(polyline.count) raw points, activity \(activity.rawValue)")
        bakeTask = Task.detached(priority: .utility) {
            let data = Self.computeGuidanceData(polyline: polyline, steps: steps, activity: activity, sampleInterval: interval)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.guidanceData = data
                self.isGenerating = false
                print("[RouteDataGenerator] Baked \(data.waypoints.count) waypoints over \(Int(data.totalDistance))m")
            }
        }
    }

    /// The actual off-main-actor work: walks the polyline once to build a cumulative
    /// distance table, locates each step's endpoint on that table (its "turn" distance),
    /// then samples a waypoint every `sampleInterval` metres, each annotated with distance
    /// so far, direction of travel, distance to the next turn, and the activity's corridor
    /// tolerance. Pure function — no shared state, safe to run off the main actor.
    nonisolated private static func computeGuidanceData(
        polyline: [CLLocationCoordinate2D],
        steps: [RouteStep],
        activity: GuidanceActivity,
        sampleInterval: CLLocationDistance
    ) -> GuidanceData {
        var cumulative: [CLLocationDistance] = [0]
        cumulative.reserveCapacity(polyline.count)
        for i in 1..<polyline.count {
            cumulative.append(cumulative[i - 1] + CompassManager.distance(from: polyline[i - 1], to: polyline[i]))
        }
        let totalDistance = cumulative.last ?? 0

        // Where each turn (every step's endpoint but the very last, which is arrival itself)
        // falls along the cumulative-distance table, so look-ahead is a cheap table lookup
        // per sample rather than a fresh geometric search.
        let turnDistances: [CLLocationDistance] = steps.dropLast().map { step in
            nearestCumulativeDistance(to: step.endCoordinate, polyline: polyline, cumulative: cumulative)
        }

        let corridorRadius = activity.corridorRadius
        var waypoints: [GuidanceWaypoint] = []
        var sampleAt: CLLocationDistance = 0

        for i in 0..<(polyline.count - 1) {
            let segmentStart = cumulative[i]
            let segmentEnd = cumulative[i + 1]
            let bearing = CompassManager.bearing(from: polyline[i], to: polyline[i + 1])
            while sampleAt >= segmentStart && sampleAt <= segmentEnd {
                let point = CompassManager.pointAlong(polyline, distance: sampleAt) ?? polyline[i]
                let nextTurn = turnDistances.first { $0 >= sampleAt } ?? totalDistance
                waypoints.append(GuidanceWaypoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    distanceFromStart: sampleAt,
                    bearing: bearing,
                    distanceToNextTurn: max(0, nextTurn - sampleAt),
                    corridorRadius: corridorRadius
                ))
                sampleAt += sampleInterval
            }
        }

        // Always cap the corridor at the true endpoint, even if it falls short of a full
        // sample interval past the last waypoint above.
        if let last = polyline.last, waypoints.last?.distanceFromStart != totalDistance {
            let bearing = polyline.count > 1
                ? CompassManager.bearing(from: polyline[polyline.count - 2], to: last)
                : 0
            waypoints.append(GuidanceWaypoint(
                latitude: last.latitude,
                longitude: last.longitude,
                distanceFromStart: totalDistance,
                bearing: bearing,
                distanceToNextTurn: 0,
                corridorRadius: corridorRadius
            ))
        }

        return GuidanceData(waypoints: waypoints, totalDistance: totalDistance, activity: activity, generatedAt: Date())
    }

    /// The cumulative distance (from the table built above) at whichever polyline vertex
    /// sits closest to `target` — used to place a step's endpoint on the same distance
    /// scale as the sampled waypoints.
    nonisolated private static func nearestCumulativeDistance(
        to target: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance]
    ) -> CLLocationDistance {
        var bestIndex = 0
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        for (i, point) in polyline.enumerated() {
            let d = CompassManager.distance(from: point, to: target)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        return cumulative[bestIndex]
    }
}
