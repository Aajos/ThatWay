//
//  RouteModels.swift
//  ThatWay
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

enum TurnSide: Codable { case left, right, straight }
enum TurnSeverity: Codable { case slight, normal, sharp, uTurn }

/// What a manoeuvre actually looks like to the traveller: which way, and how hard. For a
/// roundabout this describes the *exit* relative to the way you approach it (left, straight,
/// right) — never the entry, which is always "turn into the circle".
struct TurnShape: Codable {
    var side: TurnSide
    var severity: TurnSeverity
    static let straight = TurnShape(side: .straight, severity: .normal)

    var dir: TurnDir {
        switch side {
        case .left: return .left
        case .right: return .right
        case .straight: return .straight
        }
    }
}

enum ManeuverKind { case depart, turn, roundabout, fork, merge, ramp, keepGoing, arrive }

/// One bearing at a real intersection, and whether it's legal to turn onto (OSRM's own `entry`
/// flag) — a plain struct standing in for what was a `(bearing:entry:)` tuple before `Route`
/// needed to be `Codable` (tuples can't be); field names match exactly, so nothing reading
/// `.bearing`/`.entry` had to change.
struct RouteBearing: Codable {
    let bearing: CLLocationDirection
    let entry: Bool
}

/// One real intersection the route passes through along a step's road segment — whether the
/// route actually turns there or just continues straight through. `otherBearings` holds every
/// *other* road meeting at this point, with the road the route arrived on and the one it
/// continues along already excluded — these are the roads not taken, for `GuidanceLineView`'s
/// side-branch markers. `outBearing` (the road actually taken) is kept separately so a caller
/// can filter out "other" roads that are really just the same road's own curve re-entering the
/// graph (a roundabout's arc, a divided road's other carriageway) rather than a genuinely
/// different one.
struct RouteIntersection: Codable {
    let coordinate: CLLocationCoordinate2D
    let otherBearings: [RouteBearing]
    let outBearing: CLLocationDirection?
}

/// One turn-by-turn instruction: what to say, how far it covers, and the bearing to
/// walk/drive along for its own segment (from where the step starts to where it ends).
struct RouteStep: Identifiable, Codable {
    let id: UUID
    let instruction: String
    let distance: CLLocationDistance
    let duration: TimeInterval
    let name: String
    let maneuverType: String
    let maneuverModifier: String?
    /// Where this step's own road segment begins and ends.
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    /// The heading to point the compass along for this step, computed from
    /// `startCoordinate` to `endCoordinate` via `CompassManager.bearing`.
    let bearing: CLLocationDirection
    /// Every real intersection along this step's own road — not just its final manoeuvre
    /// point — straight from the route's own per-step intersection list.
    let intersections: [RouteIntersection]
    /// Metres along the whole route where this step's manoeuvre happens / where the next
    /// begins — how progress is measured, instead of a proximity radius that a fast
    /// traveller can step right over between two location checks.
    let startAlong: Double
    let endAlong: Double
    /// Indices into the owning `Route.geometry` where this step's own road segment starts
    /// and ends — an engine-agnostic companion to `startAlong`/`endAlong`'s distance scale.
    let startIndex: Int
    let endIndex: Int
    let turn: TurnShape
    let exitNumber: Int?
    /// True-north degrees immediately after this manoeuvre completes — a roundabout's real
    /// exit bearing, or (for `depart`) the initial heading to show as "head north" etc.
    let exitBearing: CLLocationDirection?

    var turnDirection: TurnDir { turn.dir }
}

/// A fetched route, independent of whichever `RoutingProvider` produced it: full-resolution
/// geometry plus turn-by-turn steps. `Codable` so `RoutePersistence` can save/restore the
/// active trip across a relaunch with no extra plumbing.
struct Route: Codable {
    let geometry: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let duration: TimeInterval
    let steps: [RouteStep]
    /// OSRM's per-segment road data (one entry per consecutive geometry vertex pair), scaled so
    /// they sum to `duration` — empty when the engine didn't provide annotations, or they didn't
    /// line up with `geometry`. Powers `ETAManager`; not present for every engine.
    let segmentDurations: [Double]
    let segmentSpeeds: [Double]
}
