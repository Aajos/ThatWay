//
//  TripPlanner.swift
//  ThatWayCore · MapPrefetch
//
//  Multi-stop trips for exploring. Given the places worth seeing and an amount of time, choose which to visit and in what order
//  to see the most, without running out of time. In the literature this is the orienteering problem (a travelling-salesman
//  variant with a time budget and a score per stop). Small candidate lists are solved exactly; bigger ones are narrowed to the
//  best few and then solved exactly too, so the answer is the true best of those.
//
//  Travel times come from a closure, so the same planner works with road-network times (OSRM's table service) when online and
//  with straight-line estimates when offline.
//

import CoreLocation

public struct TripCandidate: Identifiable, Sendable {
    public var id: String
    public var coordinate: CLLocationCoordinate2D
    /// How much seeing it is worth (see `TourismScorer`).
    public var score: Double
    /// Seconds spent there.
    public var dwell: TimeInterval
    /// Seconds from the start when it opens and closes; nil for always open. Arriving early waits for it to open.
    public var opens: TimeInterval?
    public var closes: TimeInterval?
    public init(id: String, coordinate: CLLocationCoordinate2D, score: Double, dwell: TimeInterval = 20 * 60, opens: TimeInterval? = nil, closes: TimeInterval? = nil) {
        self.id = id; self.coordinate = coordinate; self.score = score; self.dwell = dwell; self.opens = opens; self.closes = closes
    }
}

public struct TripRequest: Sendable {
    public var start: CLLocationCoordinate2D
    /// Where the trip must finish; nil means anywhere (an open ramble).
    public var end: CLLocationCoordinate2D?
    /// Total seconds available, travel and dwell together.
    public var budget: TimeInterval
    /// Stops that must be included (the hotel pickup, the dinner booking). The plan fails if they cannot fit.
    public var mustVisit: Set<String>
    public init(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D? = nil, budget: TimeInterval, mustVisit: Set<String> = []) {
        self.start = start; self.end = end; self.budget = budget; self.mustVisit = mustVisit
    }
}

public struct TripPlan: Equatable, Sendable {
    public var order: [String]
    public var totalScore: Double
    /// Seconds used, including waiting for opening times and the trip to the end point.
    public var totalSeconds: TimeInterval
    public var feasible: Bool
}

public enum TripPlanner {
    /// Past this many candidates the list is narrowed before the exact search (2^n states).
    public static let exactLimit = 13

    public static func plan(candidates all: [TripCandidate], request: TripRequest, travelSeconds: (CLLocationCoordinate2D, CLLocationCoordinate2D) -> TimeInterval) -> TripPlan {
        let candidates = narrow(all, request: request, travelSeconds: travelSeconds)
        let n = candidates.count
        guard n > 0 else {
            let direct = request.end.map { travelSeconds(request.start, $0) } ?? 0
            return TripPlan(order: [], totalScore: 0, totalSeconds: direct, feasible: request.mustVisit.isEmpty && direct <= request.budget)
        }
        let must = candidates.indices.reduce(0) { request.mustVisit.contains(candidates[$1].id) ? $0 | (1 << $1) : $0 }
        let missingMust = request.mustVisit.subtracting(candidates.map(\.id))
        if !missingMust.isEmpty { return TripPlan(order: [], totalScore: 0, totalSeconds: 0, feasible: false) }

        // finish[mask][last] = the earliest time (seconds from the start) the trip can be at `last` having visited exactly `mask`.
        var finish = [[TimeInterval]](repeating: [TimeInterval](repeating: .infinity, count: n), count: 1 << n)
        var from = [[Int]](repeating: [Int](repeating: -1, count: n), count: 1 << n)
        func depart(at time: TimeInterval, to j: Int, travel: TimeInterval) -> TimeInterval? {
            var arrive = time + travel
            let c = candidates[j]
            if let opens = c.opens { arrive = max(arrive, opens) }       // wait until it opens
            if let closes = c.closes, arrive > closes { return nil }       // too late
            return arrive + c.dwell
        }
        for j in 0..<n {
            if let t = depart(at: 0, to: j, travel: travelSeconds(request.start, candidates[j].coordinate)) { finish[1 << j][j] = t; from[1 << j][j] = -2 }
        }
        for mask in 1..<(1 << n) {
            for last in 0..<n where finish[mask][last] < .infinity {
                for next in 0..<n where mask & (1 << next) == 0 {
                    let travel = travelSeconds(candidates[last].coordinate, candidates[next].coordinate)
                    guard let t = depart(at: finish[mask][last], to: next, travel: travel) else { continue }
                    let nm = mask | (1 << next)
                    if t < finish[nm][next] { finish[nm][next] = t; from[nm][next] = last }
                }
            }
        }

        var best: (score: Double, time: TimeInterval, mask: Int, last: Int)?
        for mask in 1..<(1 << n) where mask & must == must {
            let score = candidates.indices.reduce(0.0) { mask & (1 << $1) != 0 ? $0 + candidates[$1].score : $0 }
            for last in 0..<n where finish[mask][last] < .infinity {
                let total = finish[mask][last] + (request.end.map { travelSeconds(candidates[last].coordinate, $0) } ?? 0)
                guard total <= request.budget else { continue }
                if best == nil || score > best!.score + 1e-9 || (abs(score - best!.score) <= 1e-9 && total < best!.time) { best = (score, total, mask, last) }
            }
        }
        guard let b = best else {
            let direct = request.end.map { travelSeconds(request.start, $0) } ?? 0
            return TripPlan(order: [], totalScore: 0, totalSeconds: direct, feasible: must == 0 && direct <= request.budget)
        }
        var order: [String] = []
        var mask = b.mask, last = b.last
        while last >= 0 {
            order.append(candidates[last].id)
            let previous = from[mask][last]
            mask &= ~(1 << last)
            last = previous
        }
        return TripPlan(order: order.reversed(), totalScore: b.score, totalSeconds: b.time, feasible: true)
    }

    /// Keeps the candidates most worth considering when there are too many for the exact search: the must-visits, then those with the
    /// most score for the time it costs to reach and see them.
    static func narrow(_ all: [TripCandidate], request: TripRequest, travelSeconds: (CLLocationCoordinate2D, CLLocationCoordinate2D) -> TimeInterval) -> [TripCandidate] {
        guard all.count > exactLimit else { return all }
        let must = all.filter { request.mustVisit.contains($0.id) }
        let rest = all.filter { !request.mustVisit.contains($0.id) }
            .filter { travelSeconds(request.start, $0.coordinate) + $0.dwell <= request.budget }
            .sorted { a, b in
                let da = a.score / max(60, travelSeconds(request.start, a.coordinate) + a.dwell)
                let db = b.score / max(60, travelSeconds(request.start, b.coordinate) + b.dwell)
                return da != db ? da > db : a.id < b.id
            }
        return Array((must + rest).prefix(exactLimit))
    }

    /// Straight-line travel time at a mode's pace, with a detour factor for streets: the offline fallback.
    public static func estimatedTravel(mode: TravelMode) -> (CLLocationCoordinate2D, CLLocationCoordinate2D) -> TimeInterval {
        let speed: Double
        switch mode { case .walk: speed = 1.3; case .run: speed = 2.8; case .cycle: speed = 4.5; case .drive: speed = 11 }
        return { a, b in TileMath.distance(a, b) * 1.3 / speed }
    }
}

/// Turns what is known about a place into a score for the trip planner and the prefetcher.
public struct TourismProfile: Sendable {
    /// Weight per category, 0...1 (history 1, shopping 0.2).
    public var interests: [String: Double]
    public init(interests: [String: Double]) { self.interests = interests }
}

public struct PlaceInfo: Sendable {
    public var categories: [String]
    /// 0...1 how well known it is (for example from how many language editions of an encyclopaedia cover it).
    public var popularity: Double
    public var isOpenNow: Bool?
    public init(categories: [String], popularity: Double, isOpenNow: Bool? = nil) { self.categories = categories; self.popularity = popularity; self.isOpenNow = isOpenNow }
}

public enum TourismScorer {
    /// 0...1. How much someone with this profile would enjoy the place: their best-matching interest, lifted by how well known it is,
    /// and cut when it is closed. A well-known place outside their interests still scores a little (a landmark is a landmark).
    public static func score(_ place: PlaceInfo, profile: TourismProfile) -> Double {
        let match = place.categories.compactMap { profile.interests[$0] }.max() ?? 0.15
        let value = match * (0.6 + 0.4 * max(0, min(1, place.popularity)))
        return place.isOpenNow == false ? value * 0.2 : value
    }
}
