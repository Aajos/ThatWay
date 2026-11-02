//
//  PrefetchPlanner.swift
//  ThatWayCore · MapPrefetch
//
//  Decides WHERE and HOW MUCH of a map to download while someone travels. It is a pure function from "where they are, where
//  they are going, what the network and battery allow" to an ordered list of tiles with a deadline each. It does no networking
//  and knows nothing about any map provider: whatever serves the tiles only has to turn a `TileID` into bytes.
//
//  The decision has four layers, each simple on its own:
//
//   1. POLICY   How far ahead, and how many bytes, this round may spend: wifi and charging buy the whole trip; cellular buys the
//               next few minutes; Low Data Mode, roaming and a low battery shrink it to what is needed right now; a dead zone
//               ahead stretches it, so the map is in hand before the tunnel.
//   2. NEED     A probability and a deadline for every tile, from the sources in `NeedModel` (route, alternatives, stops,
//               attractions, the person themself). Detail falls off with distance from the path: radius(z) = base × 2^(max−z).
//   3. SELECT   Best value for the bytes first (likely, useful at this zoom, needed soon), inside the budget. Choosing a tile
//               brings in its missing parents, so the map always zooms out cleanly, and when money runs short it is the far,
//               fine detail that is dropped, never the street around the person or the overview above it.
//   4. CHECK    Replays the downloads against the measured throughput to say honestly which tiles will arrive late.
//

import CoreLocation

// MARK: - What the planner is told

public enum NetworkKind: String, Codable, Sendable { case none, wifi, cellular }

public struct Connectivity: Sendable {
    public var kind: NetworkKind
    public var isLowDataMode: Bool
    public var isRoaming: Bool
    /// Recent measured throughput in bytes a second; 0 when unknown (then no lateness is reported).
    public var throughput: Double
    /// 0...1
    public var batteryFraction: Double
    public var isCharging: Bool

    public init(kind: NetworkKind, isLowDataMode: Bool = false, isRoaming: Bool = false, throughput: Double = 0, batteryFraction: Double = 1, isCharging: Bool = false) {
        self.kind = kind; self.isLowDataMode = isLowDataMode; self.isRoaming = isRoaming; self.throughput = throughput
        self.batteryFraction = batteryFraction; self.isCharging = isCharging
    }
}

/// A stretch of the journey (seconds from now) where the network is expected to be missing.
public struct DeadZone: Equatable, Sendable {
    public var start: TimeInterval, end: TimeInterval
    public init(start: TimeInterval, end: TimeInterval) { self.start = start; self.end = end }
}

public struct PlannedPath: Sendable {
    public var vertices: [CLLocationCoordinate2D]
    /// Seconds from now at each vertex.
    public var etas: [TimeInterval]
    public init(vertices: [CLLocationCoordinate2D], etas: [TimeInterval]) { self.vertices = vertices; self.etas = etas }

    /// The rest of a fetched route, from vertex `index`, with times taken from the route's own segment durations when it has them.
    public init(route: Route, fromVertex index: Int = 0) {
        let start = max(0, min(index, max(0, route.geometry.count - 1)))
        let v = Array(route.geometry[start...])
        var t = 0.0
        var etas = [0.0]
        let perMetre = route.distance > 0 ? route.duration / route.distance : 0
        for i in 1..<max(1, v.count) {
            let globalSegment = start + i - 1
            if route.segmentDurations.indices.contains(globalSegment) { t += route.segmentDurations[globalSegment] }
            else { t += TileMath.distance(v[i - 1], v[i]) * perMetre }
            etas.append(t)
        }
        self.init(vertices: v, etas: v.isEmpty ? [] : etas)
    }
}

public struct Stop: Sendable {
    public var coordinate: CLLocationCoordinate2D
    public var eta: TimeInterval
    /// How long they will stay and wander (seconds): a longer stay means a wider area of detailed map.
    public var dwell: TimeInterval
    public init(coordinate: CLLocationCoordinate2D, eta: TimeInterval, dwell: TimeInterval = 0) { self.coordinate = coordinate; self.eta = eta; self.dwell = dwell }
}

public struct PointOfInterest: Identifiable, Sendable {
    public var id: String
    public var coordinate: CLLocationCoordinate2D
    /// 0...1: how worth seeing it is (see `TourismScorer`).
    public var attractiveness: Double
    public init(id: String, coordinate: CLLocationCoordinate2D, attractiveness: Double) { self.id = id; self.coordinate = coordinate; self.attractiveness = attractiveness }
}

public struct PrefetchInput {
    public var mode: TravelMode
    public var position: CLLocationCoordinate2D
    public var heading: CLLocationDirection?
    /// Metres a second.
    public var speed: Double
    public var gpsAccuracy: Double
    public var route: PlannedPath?
    /// Other routes they might take, with how likely each is (multi-routing).
    public var alternatives: [(path: PlannedPath, probability: Double)]
    public var stops: [Stop]
    public var pointsOfInterest: [PointOfInterest]
    /// 0 (ignore attractions) ... 1 (an explorer).
    public var tourismInterest: Double
    public var connectivity: Connectivity
    public var deadZones: [DeadZone]
    /// Tiles already on the device.
    public var cached: Set<TileID>
    /// What the map store may still take, in bytes.
    public var remainingBytes: Int

    public init(mode: TravelMode, position: CLLocationCoordinate2D, heading: CLLocationDirection? = nil, speed: Double = 0, gpsAccuracy: Double = 10,
                route: PlannedPath? = nil, alternatives: [(path: PlannedPath, probability: Double)] = [], stops: [Stop] = [],
                pointsOfInterest: [PointOfInterest] = [], tourismInterest: Double = 0, connectivity: Connectivity, deadZones: [DeadZone] = [],
                cached: Set<TileID> = [], remainingBytes: Int) {
        self.mode = mode; self.position = position; self.heading = heading; self.speed = speed; self.gpsAccuracy = gpsAccuracy
        self.route = route; self.alternatives = alternatives; self.stops = stops; self.pointsOfInterest = pointsOfInterest
        self.tourismInterest = tourismInterest; self.connectivity = connectivity; self.deadZones = deadZones; self.cached = cached
        self.remainingBytes = remainingBytes
    }
}

// MARK: - Per-mode tuning

/// The numbers that differ by how someone moves. They are starting points to be tuned on real trips, like `ModeTuning`.
public struct PrefetchTuning: Sendable {
    public var maxZoom: Int
    public var minZoom: Int
    /// Half-width in metres of the finest-detail corridor around the route.
    public var corridor: Double
    /// Around the person themself, at the finest zoom.
    public var positionRadius: Double
    /// Seconds ahead to fetch on cellular.
    public var cellularHorizon: TimeInterval
    /// Most bytes one planning round may spend on cellular.
    public var cellularRoundBytes: Int
    /// Most bytes a whole-trip download on wifi may use.
    public var tripPackBytes: Int
    /// How long, after leaving the path, before the route is recalculated (the corridor must cover that drift).
    public var rerouteSeconds: Double

    public static func `for`(_ mode: TravelMode) -> PrefetchTuning {
        switch mode {
        case .walk:  return PrefetchTuning(maxZoom: 17, minZoom: 9, corridor: 120, positionRadius: 250, cellularHorizon: 15 * 60, cellularRoundBytes: 20_000_000, tripPackBytes: 150_000_000, rerouteSeconds: 20)
        case .run:   return PrefetchTuning(maxZoom: 17, minZoom: 9, corridor: 150, positionRadius: 300, cellularHorizon: 12 * 60, cellularRoundBytes: 20_000_000, tripPackBytes: 150_000_000, rerouteSeconds: 20)
        case .cycle: return PrefetchTuning(maxZoom: 16, minZoom: 9, corridor: 250, positionRadius: 500, cellularHorizon: 12 * 60, cellularRoundBytes: 25_000_000, tripPackBytes: 200_000_000, rerouteSeconds: 20)
        case .drive: return PrefetchTuning(maxZoom: 15, minZoom: 8, corridor: 600, positionRadius: 1000, cellularHorizon: 8 * 60, cellularRoundBytes: 30_000_000, tripPackBytes: 250_000_000, rerouteSeconds: 20)
        }
    }
}

// MARK: - Cost of a tile

public protocol TileCostModel {
    /// Bytes this tile is expected to take.
    func bytes(for tile: TileID) -> Int
}

/// A fixed guess per zoom, until real tile sizes have been measured. Dense city tiles are several times a rural one, so this is
/// deliberately a placeholder: `LearnedCostModel` replaces it with what was actually downloaded.
public struct FlatCostModel: TileCostModel {
    public var perZoom: [Int: Int]
    public var fallback: Int
    public init(perZoom: [Int: Int] = [8: 40_000, 9: 40_000, 10: 45_000, 11: 50_000, 12: 55_000, 13: 60_000, 14: 60_000, 15: 50_000, 16: 40_000, 17: 30_000], fallback: Int = 40_000) {
        self.perZoom = perZoom; self.fallback = fallback
    }
    public func bytes(for tile: TileID) -> Int { perZoom[tile.z] ?? fallback }
}

/// Learns what tiles really weigh: an exponential average of the sizes actually downloaded at each zoom, starting from a guess.
public struct LearnedCostModel: TileCostModel {
    public private(set) var perZoom: [Int: Double]
    public var fallback: Double
    public let smoothing: Double

    public init(initial: TileCostModel = FlatCostModel(), smoothing: Double = 0.2) {
        var table: [Int: Double] = [:]
        for z in 0...20 { table[z] = Double(initial.bytes(for: TileID(z: z, x: 0, y: 0))) }
        perZoom = table; fallback = Double(initial.bytes(for: TileID(z: 21, x: 0, y: 0))); self.smoothing = smoothing
    }

    public mutating func observe(tile: TileID, bytes: Int) {
        let old = perZoom[tile.z] ?? fallback
        perZoom[tile.z] = old + smoothing * (Double(bytes) - old)
    }

    public func bytes(for tile: TileID) -> Int { Int((perZoom[tile.z] ?? fallback).rounded()) }
}

// MARK: - Policy

public struct PrefetchPolicy: Equatable, Sendable {
    /// Seconds ahead to plan; nil means the whole trip.
    public var horizon: TimeInterval?
    public var maxBytes: Int
    /// Only what is needed in the next minutes (roaming, a low battery).
    public var essentialOnly: Bool
    public var reason: String

    public static func resolve(connectivity c: Connectivity, tuning: PrefetchTuning, remainingBytes: Int, deadZones: [DeadZone]) -> PrefetchPolicy {
        guard c.kind != .none else { return PrefetchPolicy(horizon: 0, maxBytes: 0, essentialOnly: true, reason: "offline") }
        let lowBattery = c.batteryFraction < 0.15 && !c.isCharging
        if c.isRoaming || lowBattery {
            return PrefetchPolicy(horizon: 180, maxBytes: min(remainingBytes, 3_000_000), essentialOnly: true, reason: c.isRoaming ? "roaming" : "low battery")
        }
        var policy: PrefetchPolicy
        if c.kind == .wifi {
            policy = PrefetchPolicy(horizon: nil, maxBytes: min(remainingBytes, tuning.tripPackBytes), essentialOnly: false, reason: "wifi: whole trip")
        } else if c.isLowDataMode {
            policy = PrefetchPolicy(horizon: tuning.cellularHorizon / 3, maxBytes: min(remainingBytes, tuning.cellularRoundBytes / 4), essentialOnly: false, reason: "cellular, Low Data Mode")
        } else {
            policy = PrefetchPolicy(horizon: tuning.cellularHorizon, maxBytes: min(remainingBytes, tuning.cellularRoundBytes), essentialOnly: false, reason: "cellular: next few minutes")
        }
        // A dead zone coming up: fetch everything up to when coverage returns, plus a minute, while there is still a signal.
        if var h = policy.horizon {
            var stretched = false
            for zone in deadZones.sorted(by: { $0.start < $1.start }) where zone.start <= h * 2 && zone.end + 60 > h {
                h = zone.end + 60; stretched = true
            }
            if stretched {
                policy.horizon = h
                policy.maxBytes = min(remainingBytes, tuning.tripPackBytes)
                policy.reason += ", stretched over a dead zone"
            }
        }
        return policy
    }
}

// MARK: - The plan

public struct TileRequest: Equatable, Sendable {
    public var tile: TileID
    /// Seconds from now until it could be needed (after dead zones are taken into account).
    public var deadline: TimeInterval
    /// Likelihood it is wanted, 0...1.
    public var p: Double
    public var estimatedBytes: Int
    public var reason: NeedSource.Kind
}

public enum PrefetchRisk: Equatable, Sendable {
    case offline
    /// Tiles that, at the measured speed, will arrive after they are needed; the first such moment.
    case lateTiles(count: Int, firstAt: TimeInterval)
    /// The budget cut some detail: how many tiles were left out.
    case detailCutForBudget(tiles: Int)
    /// A dead zone starts before everything needed for it can arrive.
    case notReadyForDeadZone(at: TimeInterval)
}

public struct PrefetchPlan: Sendable {
    public var requests: [TileRequest]
    public var estimatedBytes: Int
    public var policy: PrefetchPolicy
    public var risks: [PrefetchRisk]
    public var droppedTiles: Int
    /// Tiles per zoom level, for showing "what will I get".
    public var tilesPerZoom: [Int: Int] { Dictionary(grouping: requests, by: { $0.tile.z }).mapValues(\.count) }
}

public enum PrefetchPlanner {
    /// A safety margin before a tile is needed.
    static let deadlineMargin: TimeInterval = 10
    /// How quickly the value of a tile fades with how long until it is needed: after this many seconds it is worth about 37% of a tile needed now.
    static let valueHalfLifeSeconds: TimeInterval = 1200

    /// How useful a zoom is to someone travelling this way, 1 at the finest they use, easing down to 0.3 for context.
    static func utility(zoom: Int, maxZoom: Int) -> Double { max(0.3, 1 - 0.15 * Double(maxZoom - zoom)) }

    public static func plan(_ input: PrefetchInput, cost: TileCostModel = FlatCostModel()) -> PrefetchPlan {
        let tuning = PrefetchTuning.for(input.mode)
        let policy = PrefetchPolicy.resolve(connectivity: input.connectivity, tuning: tuning, remainingBytes: input.remainingBytes, deadZones: input.deadZones)
        if input.connectivity.kind == .none {
            return PrefetchPlan(requests: [], estimatedBytes: 0, policy: policy, risks: [.offline], droppedTiles: 0)
        }
        let sources = Self.sources(for: input, tuning: tuning, policy: policy)

        // NEED: the best (most likely, soonest) hit for each tile at each zoom.
        let zoomRange = (policy.essentialOnly ? max(tuning.minZoom, tuning.maxZoom - 3) : tuning.minZoom)...tuning.maxZoom
        var byZoom: [Int: [TileID: NeedHit]] = [:]
        for z in zoomRange {
            var merged: [TileID: NeedHit] = [:]
            for s in sources {
                for (tile, hit) in NeedModel.candidates(of: s, zoom: z, horizon: policy.horizon) {
                    if var m = merged[tile] {
                        m.p = max(m.p, hit.p); m.eta = min(m.eta, hit.eta); m.distance = min(m.distance, hit.distance)
                        merged[tile] = m
                    } else { merged[tile] = hit }
                }
            }
            byZoom[z] = merged
        }

        // SELECT: best value for the bytes first. A tile's value is how likely it is wanted, times how useful that zoom is to this
        // way of travelling, times how soon (nearer is worth more, so when money runs short it is the far stretch that goes).
        // Choosing a tile also brings in its missing parents, whose bytes are counted, so the map always zooms out cleanly.
        struct Candidate { var tile: TileID; var hit: NeedHit; var bytes: Int; var density: Double }
        var candidates: [Candidate] = []
        for z in zoomRange {
            for (tile, hit) in byZoom[z] ?? [:] where !input.cached.contains(tile) {
                let bytes = max(1, cost.bytes(for: tile))
                let value = hit.p * utility(zoom: z, maxZoom: tuning.maxZoom) * exp(-hit.eta / valueHalfLifeSeconds)
                candidates.append(Candidate(tile: tile, hit: hit, bytes: bytes, density: value / Double(bytes)))
            }
        }
        candidates.sort { a, b in
            if a.density != b.density { return a.density > b.density }
            if a.tile.z != b.tile.z { return a.tile.z < b.tile.z }
            return a.tile < b.tile
        }
        var covered = input.cached
        var chosen: [TileRequest] = []
        var spent = 0, dropped = 0
        for c in candidates {
            if covered.contains(c.tile) { continue }
            // This tile and whichever of its parents are not here yet.
            var bundle: [(tile: TileID, hit: NeedHit, bytes: Int)] = [(c.tile, c.hit, c.bytes)]
            var up = c.tile
            while up.z > zoomRange.lowerBound {
                let parent = TileMath.parent(of: up, atZoom: up.z - 1)
                if covered.contains(parent) { break }
                let hit = byZoom[parent.z]?[parent] ?? c.hit
                bundle.append((parent, hit, max(1, cost.bytes(for: parent))))
                up = parent
            }
            let bundleBytes = bundle.reduce(0) { $0 + $1.bytes }
            if spent + bundleBytes > policy.maxBytes { dropped += 1; continue }
            spent += bundleBytes
            for b in bundle {
                covered.insert(b.tile)
                chosen.append(TileRequest(tile: b.tile, deadline: b.hit.eta, p: b.hit.p, estimatedBytes: b.bytes, reason: b.hit.kind))
            }
        }
        // Every tile that was wanted but did not make it counts as dropped (the loop above counts bundles, this counts tiles).
        dropped = candidates.reduce(0) { covered.contains($1.tile) ? $0 : $0 + 1 }

        // Dead zones: whatever is needed during one must be in hand before it starts (what comes after can wait for the signal).
        for i in chosen.indices {
            for zone in input.deadZones where chosen[i].deadline >= zone.start && chosen[i].deadline <= zone.end {
                chosen[i].deadline = min(chosen[i].deadline, max(0, zone.start - deadlineMargin))
            }
        }

        // Download order: what is needed soonest first (a minute at a time), coarse before fine inside a minute.
        chosen.sort { a, b in
            let ba = Int(a.deadline / 60), bb = Int(b.deadline / 60)
            if ba != bb { return ba < bb }
            if a.tile.z != b.tile.z { return a.tile.z < b.tile.z }
            return a.deadline != b.deadline ? a.deadline < b.deadline : a.tile < b.tile
        }

        // CHECK: replay the downloads at the measured speed.
        var risks: [PrefetchRisk] = []
        if dropped > 0 { risks.append(.detailCutForBudget(tiles: dropped)) }
        if input.connectivity.throughput > 0 {
            var done = 0.0
            var late = 0
            var firstLate: TimeInterval?
            for r in chosen {
                done += Double(r.estimatedBytes) / input.connectivity.throughput
                // A tile needed right now cannot be early; only tiles with some time to spare can be late.
                if r.deadline > deadlineMargin, done > r.deadline - deadlineMargin {
                    late += 1
                    firstLate = min(firstLate ?? r.deadline, r.deadline)
                }
            }
            if late > 0 { risks.append(.lateTiles(count: late, firstAt: firstLate ?? 0)) }
            for zone in input.deadZones {
                let needBefore = chosen.filter { $0.deadline <= max(0, zone.start - deadlineMargin) + 0.001 && $0.deadline >= 0 }
                let bytes = needBefore.reduce(0) { $0 + $1.estimatedBytes }
                if Double(bytes) / input.connectivity.throughput > zone.start { risks.append(.notReadyForDeadZone(at: zone.start)) }
            }
        }
        return PrefetchPlan(requests: chosen, estimatedBytes: spent, policy: policy, risks: risks, droppedTiles: dropped)
    }

    /// Turns the situation into need sources.
    static func sources(for input: PrefetchInput, tuning: PrefetchTuning, policy: PrefetchPolicy) -> [NeedSource] {
        // The corridor must cover how far someone can drift before a reroute catches up, and how wrong the GPS can be.
        let corridor = max(tuning.corridor, input.speed * tuning.rerouteSeconds * 1.5 + 3 * input.gpsAccuracy)
        var out: [NeedSource] = []

        // Around the person themself, now.
        out.append(NeedSource(kind: .position, weight: 1, geometry: .point(input.position, eta: 0), baseRadius: max(tuning.positionRadius, corridor), maxZoom: tuning.maxZoom))

        if let route = input.route, route.vertices.count > 1 {
            out.append(NeedSource(kind: .route, weight: 1, geometry: .path(route.vertices, etas: route.etas), baseRadius: corridor, maxZoom: tuning.maxZoom))
        } else if let heading = input.heading, input.speed > 0.3 {
            // No route: where they are heading, dead-reckoned. Less certain, so lighter.
            let ahead = input.speed * (policy.horizon ?? 900)
            let end = offset(input.position, bearing: heading, metres: min(ahead, 20_000))
            out.append(NeedSource(kind: .ahead, weight: 0.6, geometry: .path([input.position, end], etas: [0, policy.horizon ?? 900]), baseRadius: corridor, maxZoom: tuning.maxZoom))
        }

        for alt in input.alternatives where alt.path.vertices.count > 1 && alt.probability > 0 {
            out.append(NeedSource(kind: .alternative, weight: alt.probability, geometry: .path(alt.path.vertices, etas: alt.path.etas), baseRadius: corridor, maxZoom: tuning.maxZoom))
        }

        for stop in input.stops {
            let dwellFactor = 1 + min(1, stop.dwell / 3600)
            out.append(NeedSource(kind: .stop, weight: 1, geometry: .point(stop.coordinate, eta: stop.eta), baseRadius: 250 * dwellFactor, maxZoom: tuning.maxZoom))
        }

        // Attractions they might detour to. Each adds a small, fine-detail area, scaled by how much they like exploring, how
        // worth seeing it is, and how little extra time reaching it costs.
        if input.tourismInterest > 0 {
            let reach = max(input.speed, input.mode == .walk ? 1.3 : 1.3)
            for poi in input.pointsOfInterest {
                let (offPath, eta) = nearestOnPath(poi.coordinate, route: input.route, position: input.position)
                let detourMinutes = 2 * offPath / reach / 60
                guard detourMinutes <= 30 else { continue }
                let w = input.tourismInterest * poi.attractiveness * exp(-detourMinutes / 20)
                guard w > 0.02 else { continue }
                out.append(NeedSource(kind: .poi, weight: w, geometry: .point(poi.coordinate, eta: eta + detourMinutes * 60 / 2), baseRadius: 120, maxZoom: min(16, tuning.maxZoom)))
            }
        }
        return out
    }

    static func nearestOnPath(_ p: CLLocationCoordinate2D, route: PlannedPath?, position: CLLocationCoordinate2D) -> (distance: Double, eta: TimeInterval) {
        guard let route, route.vertices.count > 1 else { return (TileMath.distance(p, position), 0) }
        var best = (distance: Double.infinity, eta: 0.0)
        for i in 1..<route.vertices.count {
            let d = NeedModel.distance(from: p, toSegment: route.vertices[i - 1], route.vertices[i])
            if d < best.distance { best = (d, route.etas.indices.contains(i) ? route.etas[i] : 0) }
        }
        return best
    }

    static func offset(_ c: CLLocationCoordinate2D, bearing: Double, metres: Double) -> CLLocationCoordinate2D {
        let r = bearing * .pi / 180
        return CLLocationCoordinate2D(latitude: c.latitude + cos(r) * metres / TileMath.metresPerDegreeLatitude,
                                      longitude: c.longitude + sin(r) * metres / (TileMath.metresPerDegreeLongitudeAtEquator * max(0.05, cos(c.latitude * .pi / 180))))
    }
}
