//
//  DeadReckoningTests.swift
//  ThatWayTests
//
//  The estimate must move the readout smoothly between fixes, but never invent progress it
//  can't back up: not when stopped, not when heading the wrong way, not past a turn or the finish.
//

import Testing
import CoreLocation
@testable import ThatWay
import ThatWayCore

struct DeadReckoningMathTests {
    @Test func walkingSpeedCoversSpeedTimesAge() {
        let m = DeadReckoning.extraMetres(speed: 1.4, course: 90, routeBearing: 90, age: 3, distanceCap: 20)
        #expect(abs(m - 4.2) < 0.001)
    }

    @Test func stationaryOrUnknownSpeedAddsNothing() {
        #expect(DeadReckoning.extraMetres(speed: 0.3, course: 90, routeBearing: 90, age: 4, distanceCap: 20) == 0)
        #expect(DeadReckoning.extraMetres(speed: -1, course: -1, routeBearing: 90, age: 4, distanceCap: 20) == 0)
        #expect(DeadReckoning.extraMetres(speed: 1.4, course: 90, routeBearing: 90, age: 0, distanceCap: 20) == 0)
    }

    @Test func neverMoreThanTheDistanceFilterOrSixSeconds() {
        // 1.4 m/s for 6 s is 8.4 m but the walking filter is 6 m — a new fix would have arrived by then.
        #expect(DeadReckoning.extraMetres(speed: 1.4, course: 90, routeBearing: 90, age: 5, distanceCap: 6) == 6)
        // Age is capped at 6 s however stale the fix is.
        #expect(abs(DeadReckoning.extraMetres(speed: 10, course: 90, routeBearing: 90, age: 60, distanceCap: 500) - 60) < 0.001)
    }

    @Test func courseAwayFromTheRouteAddsNothing() {
        #expect(DeadReckoning.extraMetres(speed: 1.4, course: 270, routeBearing: 90, age: 3, distanceCap: 20) == 0)
        #expect(DeadReckoning.extraMetres(speed: 1.4, course: 350, routeBearing: 10, age: 3, distanceCap: 20) > 0, "wraps across north")
        #expect(DeadReckoning.extraMetres(speed: 1.4, course: -1, routeBearing: 90, age: 3, distanceCap: 20) > 0, "unknown course isn't penalised")
    }

    @Test func angularDifferenceWraps() {
        #expect(DeadReckoning.angularDifference(350, 10) == 20)
        #expect(DeadReckoning.angularDifference(10, 350) == 20)
        #expect(DeadReckoning.angularDifference(0, 180) == 180)
    }
}

@MainActor
struct DeadReckoningRouteTests {
    /// 2 km due east in 20 vertices, depart at 0, a "turn" card at 1000, arrive at 2000.
    private func makeManager() async -> RoutingManager {
        func step(_ type: String, along: Double, index: Int) -> RouteStep {
            RouteStep(id: UUID(), instruction: type, distance: 1000, duration: 100, name: "A St",
                      maneuverType: type, maneuverModifier: nil,
                      startCoordinate: .init(latitude: 0, longitude: along / 111_320), endCoordinate: .init(latitude: 0, longitude: along / 111_320),
                      bearing: 90, intersections: [], startAlong: along, endAlong: along, startIndex: index, endIndex: index,
                      turn: .straight, exitNumber: nil, exitBearing: 90)
        }
        let route = Route(
            geometry: (0...20).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 100 / 111_320) },
            distance: 2000, duration: 200,
            steps: [step("depart", along: 0, index: 0), step("turn", along: 1000, index: 10), step("arrive", along: 2000, index: 20)],
            segmentDurations: [], segmentSpeeds: []
        )
        let manager = RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: route))
        await manager.getRoute(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 0, longitude: 2000 / 111_320), profile: .walking)
        return manager
    }

    private func at(_ metres: Double) -> CLLocationCoordinate2D { .init(latitude: 0, longitude: metres / 111_320) }

    @Test func projectionAdvancesProgressBeyondTheFix() async {
        let m = await makeManager()
        m.advanceProgress(userLocation: at(300))
        let fixed = m.progressAlong
        m.projectionExtra = 5
        m.advanceProgress(userLocation: at(300))
        #expect(abs(m.progressAlong - (fixed + 5)) < 0.01)
        #expect(abs(m.fixedProgress - fixed) < 0.01)
    }

    @Test func aRealFixReplacesTheEstimate() async {
        let m = await makeManager()
        m.advanceProgress(userLocation: at(300))
        m.projectionExtra = 6
        m.advanceProgress(userLocation: at(300))
        #expect(m.progressAlong > m.fixedProgress)
        // The traveller had actually stopped: the next fix is where the last one was, with no estimate.
        m.projectionExtra = 0
        m.advanceProgress(userLocation: at(300))
        #expect(abs(m.progressAlong - 300) < 0.5)
        // Or they moved a bit less than estimated: the new fix wins.
        m.advanceProgress(userLocation: at(303))
        #expect(abs(m.progressAlong - 303) < 0.5)
    }

    @Test func subMetreEstimateChangesDoNotPublish() async {
        let m = await makeManager()
        m.advanceProgress(userLocation: at(300))
        m.projectionExtra = 4
        m.advanceProgress(userLocation: at(300))
        let before = m.progressAlong
        m.projectionExtra = 4.6
        m.advanceProgress(userLocation: at(300))
        #expect(m.progressAlong == before)
    }

    @Test func estimateStopsShortOfTheNextManoeuvre() async {
        let m = await makeManager()
        m.advanceProgress(userLocation: at(996))
        m.projectionExtra = 30
        m.advanceProgress(userLocation: at(996))
        #expect(m.progressAlong <= 1000 - 1.5 + 0.01)
        #expect(m.upcomingCard?.kind == .turn, "the card only changes on a real fix")
        #expect(m.distanceToUpcoming >= 1.4)
    }

    @Test func estimateNeverReachesArrival() async {
        let m = await makeManager()
        m.advanceProgress(userLocation: at(1990))   // past the turn: the arrive card is current
        m.projectionExtra = 50
        m.projectionArrivalMargin = 6
        m.advanceProgress(userLocation: at(1990))
        #expect(m.progressAlong <= 2000 - 6 + 0.01)
        #expect(m.upcomingCard?.kind == .arrive)
    }

    @Test func projectedPositionKeepsTheLateralOffset() async {
        let m = await makeManager()
        let offset = CLLocationCoordinate2D(latitude: 0.00005, longitude: 300 / 111_320)   // ~5.5 m beside the road
        m.advanceProgress(userLocation: offset)
        m.projectionExtra = 10
        m.advanceProgress(userLocation: offset)
        let p = m.projectedPosition(from: offset)
        #expect(abs(p.latitude - 0.00005) < 1e-9)
        #expect(abs(CompassManager.distance(from: offset, to: p) - 10) < 0.5)
    }

    @Test func coordinateAlongRouteInterpolates() async {
        let m = await makeManager()
        let c = m.coordinate(atAlong: 250)
        #expect(c != nil)
        #expect(abs(CompassManager.distance(from: c!, to: at(250))) < 0.5)
        #expect(m.coordinate(atAlong: -5) != nil)
        #expect(abs(CompassManager.distance(from: m.coordinate(atAlong: 9999)!, to: at(2000))) < 0.5)
    }
}
