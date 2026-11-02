//
//  MapPrefetchTests.swift
//  ThatWayCoreTests
//
//  The map-download planner: what it fetches, in what order, how much, and what it throws away.
//

import Testing
import Foundation
import CoreLocation
@testable import ThatWayCore

private let melbourne = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)

/// A straight path heading `bearing` degrees from `start`, with times at `speed` metres a second.
private func straightPath(from start: CLLocationCoordinate2D = melbourne, metres: Double, bearing: Double = 90, speed: Double = 1.4, vertexEvery: Double = 100) -> PlannedPath {
    var vertices = [start], etas = [0.0]
    var d = vertexEvery
    while d < metres { vertices.append(PrefetchPlanner.offset(start, bearing: bearing, metres: d)); etas.append(d / speed); d += vertexEvery }
    vertices.append(PrefetchPlanner.offset(start, bearing: bearing, metres: metres)); etas.append(metres / speed)
    return PlannedPath(vertices: vertices, etas: etas)
}

private let wifi = Connectivity(kind: .wifi)
private let cellular = Connectivity(kind: .cellular, throughput: 500_000)
private func input(_ mode: TravelMode = .walk, route: PlannedPath? = nil, _ connectivity: Connectivity = wifi, remaining: Int = 500_000_000, position: CLLocationCoordinate2D = melbourne,
                   speed: Double = 1.4, deadZones: [DeadZone] = [], cached: Set<TileID> = [], stops: [Stop] = [], pois: [PointOfInterest] = [], interest: Double = 0,
                   alternatives: [(path: PlannedPath, probability: Double)] = []) -> PrefetchInput {
    PrefetchInput(mode: mode, position: position, heading: 90, speed: speed, route: route, alternatives: alternatives, stops: stops, pointsOfInterest: pois,
                  tourismInterest: interest, connectivity: connectivity, deadZones: deadZones, cached: cached, remainingBytes: remaining)
}

struct TileMathTests {
    @Test func aPointIsInsideItsOwnTile() {
        for z in [3, 10, 14, 17] {
            let t = TileMath.tile(containing: melbourne, zoom: z)
            let b = TileMath.bounds(of: t)
            #expect(melbourne.latitude <= b.north && melbourne.latitude >= b.south && melbourne.longitude >= b.west && melbourne.longitude <= b.east)
            #expect(TileMath.distance(from: melbourne, toTile: t) == 0)
        }
    }

    @Test func knownTiles() {
        #expect(TileMath.tile(containing: CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 1) == TileID(z: 1, x: 1, y: 1))
        #expect(TileMath.tile(containing: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12), zoom: 0) == TileID(z: 0, x: 0, y: 0))
    }

    @Test func tilesHalveInSizeEachZoomIn() {
        let a = TileMath.sizeMeters(zoom: 14, latitude: -37.8), b = TileMath.sizeMeters(zoom: 15, latitude: -37.8)
        #expect(abs(a / b - 2) < 1e-9)
        #expect(abs(TileMath.sizeMeters(zoom: 0, latitude: 0) - TileMath.earthCircumference) < 1e-6)
    }

    @Test func aTilesParentsContainIt() {
        let t = TileMath.tile(containing: melbourne, zoom: 16)
        for z in 8...15 {
            let p = TileMath.parent(of: t, atZoom: z)
            #expect(p.z == z && TileMath.distance(from: TileMath.center(of: t), toTile: p) == 0)
        }
    }

    @Test func tilesNearAPointAreWithinTheRadiusAndIncludeItsOwn() {
        let found = TileMath.tiles(near: melbourne, radius: 300, zoom: 16)
        #expect(found.contains { $0.tile == TileMath.tile(containing: melbourne, zoom: 16) && $0.distance == 0 })
        #expect(found.allSatisfy { $0.distance <= 300 })
        #expect(found.count >= 1 && found.count <= 9)
    }
}

struct PrefetchPlannerTests {
    @Test func everyTileTheRouteTouchesIsFetchedAtFullDetail() {
        let path = straightPath(metres: 2000)
        let plan = PrefetchPlanner.plan(input(route: path))
        let wanted = Set(path.vertices.map { TileMath.tile(containing: $0, zoom: 17) })
        let got = Set(plan.requests.filter { $0.tile.z == 17 }.map(\.tile))
        #expect(wanted.isSubset(of: got))
        #expect(plan.requests.allSatisfy { (9...17).contains($0.tile.z) })
    }

    @Test func theMapAlwaysZoomsOutCleanly() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 3000)))
        let have = Set(plan.requests.map(\.tile))
        for r in plan.requests where r.tile.z > 9 {
            #expect(have.contains(TileMath.parent(of: r.tile, atZoom: r.tile.z - 1)), "every tile needs its parent")
        }
    }

    @Test func detailFallsAwayWithDistanceFromThePath() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 3000)))
        let perZoom = plan.tilesPerZoom
        #expect(perZoom[17]! > 0)
        // Each zoom out reaches twice as far but tiles are twice as wide, so far fewer tiles: the pyramid is about twice its finest level.
        let coarse = (9...16).reduce(0) { $0 + (perZoom[$1] ?? 0) }
        #expect(coarse < perZoom[17]! * 3)
    }

    @Test func theEstimateIsTheSumOfTheRequests() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 2000)))
        #expect(plan.estimatedBytes == plan.requests.reduce(0) { $0 + $1.estimatedBytes })
    }

    @Test func theBudgetIsNeverExceededAndTheOverviewSurvivesWhenDetailIsCut() {
        let path = straightPath(metres: 5000)
        let small = PrefetchPlanner.plan(input(route: path, remaining: 1_500_000))
        #expect(small.estimatedBytes <= 1_500_000)
        #expect(small.droppedTiles > 0)
        #expect(small.risks.contains { if case .detailCutForBudget = $0 { return true } else { return false } })
        let zooms = Set(small.requests.map(\.tile.z))
        #expect(zooms.contains(9), "the overview comes first")
        let first = small.requests.first!
        #expect(first.tile.z == 9)
        #expect(zooms.max()! <= 17)
    }

    @Test func whenBudgetRunsOutTheNearStretchKeepsItsDetail() {
        let path = straightPath(metres: 6000)
        let plan = PrefetchPlanner.plan(input(route: path, remaining: 2_500_000))
        let fine = plan.requests.filter { $0.tile.z == 17 }
        #expect(!fine.isEmpty)
        let farthestFine = fine.map(\.deadline).max()!
        let routeEnd = path.etas.last!
        #expect(farthestFine < routeEnd * 0.9, "far detail is what gets dropped")
        #expect(fine.map(\.deadline).min()! < 60, "the next stretch is kept")
    }

    @Test func downloadsAreOrderedBySoonestNeedThenCoarseToFine() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 4000)))
        var lastBucket = 0
        for r in plan.requests {
            let bucket = Int(r.deadline / 60)
            #expect(bucket >= lastBucket)
            lastBucket = bucket
        }
    }

    @Test func offlineMeansNothingToDoAndSaysSo() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 2000), Connectivity(kind: .none)))
        #expect(plan.requests.isEmpty && plan.risks == [.offline])
    }

    @Test func cachedTilesAreNotAskedForAgain() {
        let path = straightPath(metres: 1500)
        let first = PrefetchPlanner.plan(input(route: path))
        let second = PrefetchPlanner.plan(input(route: path, cached: Set(first.requests.map(\.tile))))
        #expect(second.requests.isEmpty)
    }

    @Test func cellularFetchesOnlyTheNextFewMinutesButWifiFetchesTheWholeTrip() {
        let path = straightPath(metres: 60_000, speed: 25, vertexEvery: 500)      // a drive of 40 minutes
        let onWifi = PrefetchPlanner.plan(input(.drive, route: path, wifi, speed: 25))
        let onCell = PrefetchPlanner.plan(input(.drive, route: path, cellular, speed: 25))
        #expect(onWifi.requests.map(\.deadline).max()! > 30 * 60)
        #expect(onCell.requests.map(\.deadline).max()! <= 8 * 60 + 1)
        #expect(onCell.requests.count < onWifi.requests.count)
        #expect(onCell.policy.reason.contains("cellular") && onWifi.policy.reason.contains("wifi"))
    }

    @Test func lowDataModeAndRoamingAndLowBatteryShrinkItToWhatIsNeededNow() {
        let path = straightPath(metres: 10_000, speed: 1.4)
        let normal = PrefetchPlanner.plan(input(route: path, cellular))
        let lowData = PrefetchPlanner.plan(input(route: path, Connectivity(kind: .cellular, isLowDataMode: true, throughput: 500_000)))
        let roaming = PrefetchPlanner.plan(input(route: path, Connectivity(kind: .cellular, isRoaming: true, throughput: 500_000)))
        let flat = PrefetchPlanner.plan(input(route: path, Connectivity(kind: .cellular, throughput: 500_000, batteryFraction: 0.1)))
        #expect(lowData.estimatedBytes < normal.estimatedBytes)
        #expect(roaming.estimatedBytes <= 3_000_000 && roaming.policy.essentialOnly)
        #expect(flat.policy.essentialOnly && flat.policy.reason == "low battery")
        #expect(roaming.requests.map(\.deadline).max()! <= 180)
        let charging = PrefetchPlanner.plan(input(route: path, Connectivity(kind: .cellular, throughput: 500_000, batteryFraction: 0.1, isCharging: true)))
        #expect(!charging.policy.essentialOnly)
    }

    @Test func aDeadZoneAheadStretchesTheDownloadAndMovesTheDeadlines() {
        let path = straightPath(metres: 50_000, speed: 25, vertexEvery: 500)
        let zone = DeadZone(start: 600, end: 1500)
        let without = PrefetchPlanner.plan(input(.drive, route: path, cellular, speed: 25))
        let with = PrefetchPlanner.plan(input(.drive, route: path, cellular, speed: 25, deadZones: [zone]))
        #expect(without.requests.map(\.deadline).max()! <= 8 * 60 + 1)
        #expect(with.policy.reason.contains("dead zone"))
        // Tiles needed during the dead zone are due before it starts, whatever time they would otherwise be needed.
        let during = with.requests.filter { $0.deadline > 480 }
        #expect(!during.isEmpty)
        #expect(with.requests.allSatisfy { !(zone.start...zone.end).contains($0.deadline) }, "nothing is left to be fetched while there is no signal")
        #expect(with.requests.contains { abs($0.deadline - (zone.start - 10)) < 0.001 }, "what was due in the zone is now due as it starts")
        #expect(with.estimatedBytes > without.estimatedBytes)
    }

    @Test func slowNetworksAreToldWhichTilesWillBeLate() {
        let path = straightPath(metres: 6000, speed: 1.4)
        let slow = Connectivity(kind: .cellular, throughput: 5_000)             // 5 KB/s
        let plan = PrefetchPlanner.plan(input(route: path, slow))
        #expect(plan.risks.contains { if case .lateTiles = $0 { return true } else { return false } })
        let fast = Connectivity(kind: .wifi, throughput: 50_000_000)
        #expect(PrefetchPlanner.plan(input(route: path, fast)).risks.allSatisfy { if case .lateTiles = $0 { return false } else { return true } })
    }

    @Test func aDeadZoneThatCannotBeReadyInTimeIsReported() {
        let path = straightPath(metres: 30_000, speed: 25, vertexEvery: 500)
        let slow = Connectivity(kind: .cellular, throughput: 50_000)
        let plan = PrefetchPlanner.plan(input(.drive, route: path, slow, speed: 25, deadZones: [DeadZone(start: 120, end: 900)]))
        #expect(plan.risks.contains(.notReadyForDeadZone(at: 120)))
    }

    @Test func withoutARouteItFollowsWhereThePersonIsHeading() {
        let plan = PrefetchPlanner.plan(input(route: nil, cellular, speed: 1.4))
        let kinds = Set(plan.requests.map(\.reason))
        #expect(kinds.contains(.ahead) && kinds.contains(.position))
        let east = TileMath.tile(containing: PrefetchPlanner.offset(melbourne, bearing: 90, metres: 1000), zoom: 17)
        let west = TileMath.tile(containing: PrefetchPlanner.offset(melbourne, bearing: 270, metres: 1000), zoom: 17)
        let got = Set(plan.requests.map(\.tile))
        #expect(got.contains(east) && !got.contains(west), "heading east means the street detail is east, not behind")
    }

    @Test func theCorridorWidensWithSpeedAndPoorGps() {
        let path = straightPath(metres: 3000, speed: 1.4)
        let normal = PrefetchPlanner.plan(input(route: path, speed: 1.4))
        var poor = input(route: path, speed: 1.4)
        poor.gpsAccuracy = 80
        let wide = PrefetchPlanner.plan(poor)
        #expect(wide.requests.count > normal.requests.count)
    }

    @Test func aDestinationGetsDetailAroundItAndMoreWhenTheyWillStayLonger() {
        let far = PrefetchPlanner.offset(melbourne, bearing: 0, metres: 4000)
        let brief = PrefetchPlanner.plan(input(route: nil, wifi, stops: [Stop(coordinate: far, eta: 3000, dwell: 0)]))
        let long = PrefetchPlanner.plan(input(route: nil, wifi, stops: [Stop(coordinate: far, eta: 3000, dwell: 3600)]))
        let around = TileMath.tile(containing: far, zoom: 17)
        #expect(brief.requests.contains { $0.tile == around })
        #expect(long.requests.filter { $0.reason == .stop }.count >= brief.requests.filter { $0.reason == .stop }.count)
    }

    @Test func multipleRoutesAreCoveredInProportionToHowLikelyEachIs() {
        let main = straightPath(metres: 3000, bearing: 90)
        let alt = straightPath(metres: 3000, bearing: 60)
        let none = PrefetchPlanner.plan(input(route: main))
        let both = PrefetchPlanner.plan(input(route: main, alternatives: [(alt, 0.5)]))
        #expect(both.requests.count > none.requests.count)
        let altTile = TileMath.tile(containing: alt.vertices[20], zoom: 15)
        #expect(both.requests.contains { $0.tile == altTile })
        #expect(!none.requests.contains { $0.tile == altTile })
        let tiny = PrefetchPlanner.plan(input(route: main, alternatives: [(alt, 0.0)]))
        #expect(tiny.requests.count == none.requests.count, "an impossible alternative costs nothing")
    }

    @Test func attractionsAddDetailOnlyWhenTheyAreWorthItAndNearEnough() {
        let path = straightPath(metres: 3000)
        let near = PointOfInterest(id: "near", coordinate: PrefetchPlanner.offset(PrefetchPlanner.offset(melbourne, bearing: 90, metres: 1500), bearing: 0, metres: 500), attractiveness: 0.9)
        let far = PointOfInterest(id: "far", coordinate: PrefetchPlanner.offset(melbourne, bearing: 0, metres: 20_000), attractiveness: 0.9)
        let dull = PointOfInterest(id: "dull", coordinate: PrefetchPlanner.offset(PrefetchPlanner.offset(melbourne, bearing: 90, metres: 1500), bearing: 180, metres: 500), attractiveness: 0.01)
        let off = PrefetchPlanner.plan(input(route: path, pois: [near, far, dull], interest: 0))
        let on = PrefetchPlanner.plan(input(route: path, pois: [near, far, dull], interest: 1))
        #expect(on.requests.count > off.requests.count)
        let nearTile = TileMath.tile(containing: near.coordinate, zoom: 16)
        #expect(on.requests.contains { $0.tile == nearTile })
        #expect(!off.requests.contains { $0.tile == nearTile })
        #expect(!on.requests.contains { $0.reason == .poi && TileMath.distance(from: far.coordinate, toTile: $0.tile) < 100 }, "twenty kilometres off the path is not a detour")
        let explorer = PrefetchPlanner.plan(input(route: path, pois: [near], interest: 1))
        let casual = PrefetchPlanner.plan(input(route: path, pois: [near], interest: 0.3))
        #expect(explorer.requests.filter { $0.reason == .poi }.count >= casual.requests.filter { $0.reason == .poi }.count)
    }

    @Test func driversGetCoarserDetailThanWalkers() {
        let path = straightPath(metres: 3000, speed: 12)
        let drive = PrefetchPlanner.plan(input(.drive, route: path, speed: 12))
        let walk = PrefetchPlanner.plan(input(.walk, route: path, speed: 1.4))
        #expect(drive.requests.map(\.tile.z).max()! == 15)
        #expect(walk.requests.map(\.tile.z).max()! == 17)
    }

    @Test func theSameInputAlwaysGivesTheSamePlan() {
        let a = PrefetchPlanner.plan(input(route: straightPath(metres: 2500)))
        let b = PrefetchPlanner.plan(input(route: straightPath(metres: 2500)))
        #expect(a.requests == b.requests)
    }

    @Test func aRealRouteIsReadFromItsOwnSegmentTimes() {
        let geometry = [melbourne, PrefetchPlanner.offset(melbourne, bearing: 90, metres: 100), PrefetchPlanner.offset(melbourne, bearing: 90, metres: 300)]
        let route = Route(geometry: geometry, distance: 300, duration: 300, steps: [], segmentDurations: [40, 160], segmentSpeeds: [])
        let path = PlannedPath(route: route)
        #expect(path.etas == [0, 40, 200])
        let rest = PlannedPath(route: route, fromVertex: 1)
        #expect(rest.vertices.count == 2 && rest.etas == [0, 160])
    }
}

struct CostModelTests {
    @Test func theLearnedModelMovesTowardWhatWasActuallyDownloaded() {
        var m = LearnedCostModel(initial: FlatCostModel(perZoom: [15: 50_000], fallback: 50_000), smoothing: 0.5)
        let t = TileID(z: 15, x: 1, y: 1)
        #expect(m.bytes(for: t) == 50_000)
        for _ in 0..<12 { m.observe(tile: t, bytes: 100_000) }
        #expect(abs(m.bytes(for: t) - 100_000) < 1_000)
        #expect(m.bytes(for: TileID(z: 14, x: 0, y: 0)) == 50_000, "other zooms are untouched")
    }

    @Test func aCostlierModelMeansFewerTilesForTheSameBudget() {
        let path = straightPath(metres: 4000)
        let cheap = PrefetchPlanner.plan(input(route: path, remaining: 3_000_000), cost: FlatCostModel(perZoom: [:], fallback: 20_000))
        let dear = PrefetchPlanner.plan(input(route: path, remaining: 3_000_000), cost: FlatCostModel(perZoom: [:], fallback: 80_000))
        #expect(dear.requests.count < cheap.requests.count)
        #expect(cheap.estimatedBytes <= 3_000_000 && dear.estimatedBytes <= 3_000_000)
    }
}

struct MapStoreTests {
    private func sources(_ path: PlannedPath) -> [NeedSource] {
        [NeedSource(kind: .route, weight: 1, geometry: .path(path.vertices, etas: path.etas), baseRadius: 120, maxZoom: 17)]
    }

    @Test func nothingIsEvictedWhileTheStoreFits() {
        let t = TileID(z: 15, x: 1, y: 1)
        #expect(EvictionPlanner.plan(cache: [CachedTile(tile: t, bytes: 100, age: 0)], budgetBytes: 1000, sources: []).isEmpty)
    }

    @Test func tilesFarFromTheWayAheadGoFirstAndTheWayAheadStays() {
        let ahead = straightPath(metres: 2000)
        let onRoute = TileMath.tile(containing: ahead.vertices[10], zoom: 16)
        let nearby = TileMath.tile(containing: PrefetchPlanner.offset(ahead.vertices[10], bearing: 0, metres: 200), zoom: 16)
        let farAway = TileMath.tile(containing: PrefetchPlanner.offset(melbourne, bearing: 270, metres: 30_000), zoom: 16)
        let cache = [CachedTile(tile: onRoute, bytes: 40_000, age: 10), CachedTile(tile: nearby, bytes: 40_000, age: 10), CachedTile(tile: farAway, bytes: 40_000, age: 10)]
        let evicted = EvictionPlanner.plan(cache: cache, budgetBytes: 100_000, sources: sources(ahead))
        #expect(evicted == [farAway] || (evicted.first == farAway && !evicted.contains(onRoute)))
    }

    @Test func pinnedTilesAreNeverEvicted() {
        let far = TileMath.tile(containing: PrefetchPlanner.offset(melbourne, bearing: 270, metres: 50_000), zoom: 14)
        let other = TileMath.tile(containing: PrefetchPlanner.offset(melbourne, bearing: 270, metres: 60_000), zoom: 14)
        let evicted = EvictionPlanner.plan(cache: [CachedTile(tile: far, bytes: 90, age: 9999, pinned: true), CachedTile(tile: other, bytes: 90, age: 9999)], budgetBytes: 100, sources: [])
        #expect(evicted == [other])
    }

    @Test func itFreesDownToTheLowWaterMarkNotJustUnderTheBudget() {
        let tiles = (0..<10).map { CachedTile(tile: TileID(z: 14, x: 100 + $0, y: 200), bytes: 100, age: Double($0)) }
        let evicted = EvictionPlanner.plan(cache: tiles, budgetBytes: 900, lowWater: 0.6, sources: [])
        let left = 1000 - evicted.count * 100
        #expect(left <= 540 && left > 440)
    }

    @Test func olderUnusedTilesGoBeforeRecentOnesWhenNeitherIsNeeded() {
        let old = CachedTile(tile: TileID(z: 14, x: 1, y: 1), bytes: 100, age: 48 * 3600)
        let fresh = CachedTile(tile: TileID(z: 14, x: 2, y: 2), bytes: 100, age: 60)
        #expect(EvictionPlanner.plan(cache: [old, fresh], budgetBytes: 150, lowWater: 0.7, sources: []) == [old.tile])
    }

    @Test func roundingRequestsToBlocksTradesPrivacyForBytes() {
        let plan = PrefetchPlanner.plan(input(route: straightPath(metres: 1500)))
        let o12 = PrivacyBlocks.overhead(plan.requests, blockZoom: 12)
        let o14 = PrivacyBlocks.overhead(plan.requests, blockZoom: 14)
        #expect(o12 > 1 && o14 > 1)
        #expect(o12 > o14, "a bigger block hides more and costs more")
        let groups = PrivacyBlocks.group(plan.requests, blockZoom: 12)
        #expect(groups.map(\.wanted.count).reduce(0, +) == plan.requests.filter { $0.tile.z >= 12 }.count)
    }
}

struct TripPlannerTests {
    private let here = melbourne
    private func place(_ id: String, east: Double, north: Double, score: Double, dwell: TimeInterval = 600, opens: TimeInterval? = nil, closes: TimeInterval? = nil) -> TripCandidate {
        TripCandidate(id: id, coordinate: PrefetchPlanner.offset(PrefetchPlanner.offset(here, bearing: 90, metres: east), bearing: 0, metres: north), score: score, dwell: dwell, opens: opens, closes: closes)
    }
    private let walkTime = TripPlanner.estimatedTravel(mode: .walk)

    @Test func itPicksTheMostWorthSeeingThatFitsAndOrdersThemSensibly() {
        let a = place("museum", east: 400, north: 0, score: 9)
        let b = place("park", east: 800, north: 0, score: 5)
        let c = place("faraway", east: 9000, north: 0, score: 10)
        let plan = TripPlanner.plan(candidates: [c, b, a], request: TripRequest(start: here, budget: 3600), travelSeconds: walkTime)
        #expect(plan.feasible && plan.order == ["museum", "park"])
        #expect(plan.totalScore == 14 && plan.totalSeconds <= 3600)
    }

    @Test func itNeverExceedsTheTimeBudget() {
        let cs = (0..<8).map { place("p\($0)", east: Double($0) * 300, north: Double($0 % 3) * 200, score: Double($0 + 1)) }
        for budget in [900.0, 1800, 3600, 7200] {
            let plan = TripPlanner.plan(candidates: cs, request: TripRequest(start: here, budget: budget), travelSeconds: walkTime)
            #expect(plan.totalSeconds <= budget + 0.001)
        }
    }

    @Test func itMatchesABruteForceSearchOnSmallProblems() {
        var seed: UInt64 = 7
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        for _ in 0..<6 {
            let cs = (0..<6).map { place("p\($0)", east: rnd() * 2500, north: rnd() * 2500, score: 1 + rnd() * 9, dwell: 300 + rnd() * 900) }
            let budget = 2400.0
            let plan = TripPlanner.plan(candidates: cs, request: TripRequest(start: here, budget: budget), travelSeconds: walkTime)
            // Brute force: every ordered subset.
            var best = 0.0
            func walk(_ at: CLLocationCoordinate2D, _ time: Double, _ used: Set<Int>, _ score: Double) {
                best = max(best, score)
                for i in cs.indices where !used.contains(i) {
                    let t = time + walkTime(at, cs[i].coordinate) + cs[i].dwell
                    if t <= budget { walk(cs[i].coordinate, t, used.union([i]), score + cs[i].score) }
                }
            }
            walk(here, 0, [], 0)
            #expect(abs(plan.totalScore - best) < 1e-6, "exact: \(plan.totalScore) vs \(best)")
        }
    }

    @Test func openingHoursAreRespected() {
        let early = place("bakery", east: 300, north: 0, score: 5, dwell: 600, opens: 1800)
        let shut = place("shop", east: 500, north: 0, score: 9, dwell: 600, closes: 300)
        let plan = TripPlanner.plan(candidates: [early, shut], request: TripRequest(start: here, budget: 4000), travelSeconds: walkTime)
        #expect(plan.order == ["bakery"], "it waits for the bakery to open and cannot reach the shop before it closes")
        #expect(plan.totalSeconds >= 1800 + 600)
    }

    @Test func aMustVisitIsIncludedEvenIfItScoresLittleOrTheTripFailsHonestly() {
        let boring = place("pickup", east: 600, north: 0, score: 0.1)
        let great = place("view", east: 300, north: 0, score: 10)
        let ok = TripPlanner.plan(candidates: [boring, great], request: TripRequest(start: here, budget: 4000, mustVisit: ["pickup"]), travelSeconds: walkTime)
        #expect(ok.feasible && ok.order.contains("pickup"))
        let impossible = TripPlanner.plan(candidates: [boring, great], request: TripRequest(start: here, budget: 300, mustVisit: ["pickup"]), travelSeconds: walkTime)
        #expect(!impossible.feasible)
    }

    @Test func theTripMustEndWhereItSaysItEnds() {
        let a = place("a", east: 500, north: 0, score: 5)
        let end = PrefetchPlanner.offset(here, bearing: 270, metres: 800)
        let plan = TripPlanner.plan(candidates: [a], request: TripRequest(start: here, end: end, budget: 1500), travelSeconds: walkTime)
        #expect(plan.order.isEmpty, "going to a and back to the end does not fit, so it only heads for the end")
        let roomy = TripPlanner.plan(candidates: [a], request: TripRequest(start: here, end: end, budget: 4000), travelSeconds: walkTime)
        #expect(roomy.order == ["a"])
    }

    @Test func nothingToVisitStillGetsThereOrSaysItCannot() {
        let end = PrefetchPlanner.offset(here, bearing: 90, metres: 1000)
        #expect(TripPlanner.plan(candidates: [], request: TripRequest(start: here, end: end, budget: 3600), travelSeconds: walkTime).feasible)
        #expect(!TripPlanner.plan(candidates: [], request: TripRequest(start: here, end: end, budget: 100), travelSeconds: walkTime).feasible)
    }

    @Test func manyCandidatesAreNarrowedToTheBestAndStillSolved() {
        var cs: [TripCandidate] = []
        for i in 0..<40 {
            let east = Double(i % 8) * 250
            let north = Double(i / 8) * 250
            let score = Double((i * 7) % 10) + 1
            cs.append(place("p\(i)", east: east, north: north, score: score))
        }
        let budget: TimeInterval = 3 * 3600
        let plan = TripPlanner.plan(candidates: cs, request: TripRequest(start: here, budget: budget), travelSeconds: walkTime)
        #expect(plan.feasible)
        #expect(!plan.order.isEmpty)
        #expect(plan.totalSeconds <= budget + 0.001)
        #expect(Set(plan.order).count == plan.order.count, "no place twice")
    }

    @Test func scoresFollowInterestsPopularityAndOpeningTimes() {
        let history = TourismProfile(interests: ["history": 1, "shopping": 0.2])
        let museum = PlaceInfo(categories: ["history"], popularity: 1)
        let mall = PlaceInfo(categories: ["shopping"], popularity: 1)
        #expect(TourismScorer.score(museum, profile: history) > TourismScorer.score(mall, profile: history))
        #expect(TourismScorer.score(PlaceInfo(categories: ["history"], popularity: 0), profile: history) < TourismScorer.score(museum, profile: history))
        #expect(TourismScorer.score(PlaceInfo(categories: ["history"], popularity: 1, isOpenNow: false), profile: history) < TourismScorer.score(museum, profile: history))
        #expect(TourismScorer.score(PlaceInfo(categories: ["other"], popularity: 1), profile: history) > 0, "a landmark is still a landmark")
    }
}
