//
//  RouteModels.swift
//  ThatWayCore
//
//  The app's own route model — what every consumer (compass, cards, polyline, persistence)
//  reads. Nothing here knows OSRM exists; `OSRMRoutingProvider` is the only file that
//  translates OSRM's JSON into these types, so a future engine swap only touches that one file.
//

import CoreLocation

extension CLLocationCoordinate2D: @retroactive Codable {
    private enum CodingKeys: String, CodingKey { case latitude, longitude }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            latitude: try container.decode(CLLocationDegrees.self, forKey: .latitude),
            longitude: try container.decode(CLLocationDegrees.self, forKey: .longitude)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

public enum TurnSide: Codable { case left, right, straight }
public enum TurnSeverity: Codable { case slight, normal, sharp, uTurn }

public enum TurnDir { case left, right, straight }

/// What a manoeuvre actually looks like to the traveller: which way, and how hard. For a
/// roundabout this describes the *exit* relative to the way you approach it (left, straight,
/// right) — never the entry, which is always "turn into the circle".
public struct TurnShape: Codable {
    public var side: TurnSide
    public var severity: TurnSeverity
    public init(side: TurnSide, severity: TurnSeverity) { self.side = side; self.severity = severity }
    public static let straight = TurnShape(side: .straight, severity: .normal)

    public var dir: TurnDir {
        switch side {
        case .left: return .left
        case .right: return .right
        case .straight: return .straight
        }
    }
}

public enum ManeuverKind { case depart, turn, roundabout, fork, merge, ramp, keepGoing, arrive }

/// One bearing at a real intersection, and whether it's legal to turn onto (OSRM's own `entry`
/// flag) — a plain struct standing in for what was a `(bearing:entry:)` tuple before `Route`
/// needed to be `Codable` (tuples can't be); field names match exactly, so nothing reading
/// `.bearing`/`.entry` had to change.
public struct RouteBearing: Codable {
    public let bearing: CLLocationDirection
    public let entry: Bool
    public init(bearing: CLLocationDirection, entry: Bool) { self.bearing = bearing; self.entry = entry }
}

/// One real intersection the route passes through along a step's road segment — whether the
/// route actually turns there or just continues straight through. `otherBearings` holds every
/// *other* road meeting at this point, with the road the route arrived on and the one it
/// continues along already excluded — these are the roads not taken, for `GuidanceLineView`'s
/// side-branch markers. `outBearing` (the road actually taken) is kept separately so a caller
/// can filter out "other" roads that are really just the same road's own curve re-entering the
/// graph (a roundabout's arc, a divided road's other carriageway) rather than a genuinely
/// different one.
public struct RouteIntersection: Codable {
    public let coordinate: CLLocationCoordinate2D
    public let otherBearings: [RouteBearing]
    public let outBearing: CLLocationDirection?
    public init(coordinate: CLLocationCoordinate2D, otherBearings: [RouteBearing], outBearing: CLLocationDirection?) {
        self.coordinate = coordinate; self.otherBearings = otherBearings; self.outBearing = outBearing
    }
}

/// One turn-by-turn instruction: what to say, how far it covers, and the bearing to
/// walk/drive along for its own segment (from where the step starts to where it ends).
public struct RouteStep: Identifiable, Codable {
    public let id: UUID
    public let instruction: String
    public let distance: CLLocationDistance
    public let duration: TimeInterval
    public let name: String
    public let maneuverType: String
    public let maneuverModifier: String?
    /// Where this step's own road segment begins and ends.
    public let startCoordinate: CLLocationCoordinate2D
    public let endCoordinate: CLLocationCoordinate2D
    /// The heading to point the compass along for this step, computed from
    /// `startCoordinate` to `endCoordinate` via `CompassManager.bearing`.
    public let bearing: CLLocationDirection
    /// Every real intersection along this step's own road — not just its final manoeuvre
    /// point — straight from the route's own per-step intersection list.
    public let intersections: [RouteIntersection]
    /// Metres along the whole route where this step's manoeuvre happens / where the next
    /// begins — how progress is measured, instead of a proximity radius that a fast
    /// traveller can step right over between two location checks.
    public let startAlong: Double
    public let endAlong: Double
    /// Indices into the owning `Route.geometry` where this step's own road segment starts
    /// and ends — an engine-agnostic companion to `startAlong`/`endAlong`'s distance scale.
    public let startIndex: Int
    public let endIndex: Int
    public let turn: TurnShape
    public let exitNumber: Int?
    /// True-north degrees immediately after this manoeuvre completes — a roundabout's real
    /// exit bearing, or (for `depart`) the initial heading to show as "head north" etc.
    public let exitBearing: CLLocationDirection?

    public var turnDirection: TurnDir { turn.dir }

    public init(
        id: UUID, instruction: String, distance: CLLocationDistance, duration: TimeInterval, name: String,
        maneuverType: String, maneuverModifier: String?, startCoordinate: CLLocationCoordinate2D, endCoordinate: CLLocationCoordinate2D,
        bearing: CLLocationDirection, intersections: [RouteIntersection], startAlong: Double, endAlong: Double,
        startIndex: Int, endIndex: Int, turn: TurnShape, exitNumber: Int?, exitBearing: CLLocationDirection?
    ) {
        self.id = id; self.instruction = instruction; self.distance = distance; self.duration = duration; self.name = name
        self.maneuverType = maneuverType; self.maneuverModifier = maneuverModifier
        self.startCoordinate = startCoordinate; self.endCoordinate = endCoordinate; self.bearing = bearing
        self.intersections = intersections; self.startAlong = startAlong; self.endAlong = endAlong
        self.startIndex = startIndex; self.endIndex = endIndex; self.turn = turn
        self.exitNumber = exitNumber; self.exitBearing = exitBearing
    }
}

/// A fetched route, independent of whichever `RoutingProvider` produced it: full-resolution
/// geometry plus turn-by-turn steps. `Codable` so `RoutePersistence` can save/restore the
/// active trip across a relaunch with no extra plumbing.
public struct Route: Codable {
    public let geometry: [CLLocationCoordinate2D]
    public let distance: CLLocationDistance
    public let duration: TimeInterval
    public let steps: [RouteStep]
    /// OSRM's per-segment road data (one entry per consecutive geometry vertex pair), scaled so
    /// they sum to `duration` — empty when the engine didn't provide annotations, or they didn't
    /// line up with `geometry`. Powers `ETAManager`; not present for every engine.
    public let segmentDurations: [Double]
    public let segmentSpeeds: [Double]

    public init(geometry: [CLLocationCoordinate2D], distance: CLLocationDistance, duration: TimeInterval, steps: [RouteStep],
                segmentDurations: [Double], segmentSpeeds: [Double]) {
        self.geometry = geometry; self.distance = distance; self.duration = duration; self.steps = steps
        self.segmentDurations = segmentDurations; self.segmentSpeeds = segmentSpeeds
    }
}
