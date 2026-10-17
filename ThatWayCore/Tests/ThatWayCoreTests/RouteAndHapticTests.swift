import Testing
import Foundation
import CoreLocation
@testable import ThatWayCore

struct RouteTrackerTests {
    private let start = CLLocationCoordinate2D(latitude: 10, longitude: 20)

    private func makeRoute() -> Route {
        SyntheticRoute.make(from: start, initialBearing: 0, legs: [.init(metres: 300, turn: .right), .init(metres: 200, turn: .left), .init(metres: 100)])
    }

    @Test func syntheticRouteHasTheRightShape() {
        let r = makeRoute()
        #expect(abs(r.distance - 600) < 0.001)
        #expect(r.steps.map(\.maneuverType) == ["depart", "turn", "turn", "arrive"])
        #expect(r.steps[1].turn.side == .right && r.steps[2].turn.side == .left)
        #expect(abs(r.steps[1].startAlong - 300) < 0.001 && abs(r.steps[2].startAlong - 500) < 0.001)
        // After a right turn from north the route heads east.
        let a = r.geometry[16], b = r.geometry[17]
        #expect(AngleMath.difference(CompassManager.bearing(from: a, to: b), 90) < 1)
    }

    @Test func reportsDistanceAndTurnToTheNextWaypoint() {
        var t = RouteTracker(route: makeRoute())
        let p = t.update(position: SyntheticRoute.offset(start, bearing: 0, metres: 100))
        #expect(abs(p.along - 100) < 2)
        #expect(abs(p.distanceToNext - 200) < 3)
        #expect(p.nextTurn?.side == .right)
        #expect(p.nextStepIndex == 1)
        #expect(!p.offRoute && !p.arrived)
    }

    @Test func movesOnToTheNextTurnAfterPassingOne() {
        var t = RouteTracker(route: makeRoute())
        _ = t.update(position: SyntheticRoute.offset(start, bearing: 0, metres: 295))
        let corner = SyntheticRoute.offset(start, bearing: 0, metres: 300)
        let p = t.update(position: SyntheticRoute.offset(corner, bearing: 90, metres: 20))
        #expect(p.nextTurn?.side == .left)
        #expect(abs(p.distanceToNext - 180) < 4)
    }

    @Test func detectsOffRouteAndArrival() {
        var t = RouteTracker(route: makeRoute(), mode: .walk)
        let off = t.update(position: SyntheticRoute.offset(SyntheticRoute.offset(start, bearing: 0, metres: 100), bearing: 90, metres: 40))
        #expect(off.offRoute, "40 m beside the road is outside the 15 m walking corridor")

        var t2 = RouteTracker(route: makeRoute(), mode: .walk)
        var last = SyntheticRoute.offset(start, bearing: 0, metres: 0)
        for m in stride(from: 0.0, through: 300.0, by: 20) { last = SyntheticRoute.offset(start, bearing: 0, metres: m); _ = t2.update(position: last) }
        let end = makeRoute().geometry.last!
        let p = t2.update(position: end)
        #expect(p.arrived)
        #expect(p.nextTurn == nil)
    }

    @Test func progressNeverGoesBackward() {
        var t = RouteTracker(route: makeRoute())
        _ = t.update(position: SyntheticRoute.offset(start, bearing: 0, metres: 150))
        let back = t.update(position: SyntheticRoute.offset(start, bearing: 0, metres: 140))
        #expect(back.along >= 149)
    }
}

struct HapticPatternTests {
    @Test func everyCandidateSetHasFourPatternsThatAllDiffer() {
        for set in HapticLibrary.all {
            #expect(set.patterns.count == 4)
            let beatLists = set.patterns.map { $0.beats }
            for i in beatLists.indices { for j in beatLists.indices where i < j {
                #expect(beatLists[i] != beatLists[j], "\(set.name): patterns \(i) and \(j) are identical")
            } }
        }
    }

    @Test func leftAndRightDifferByCountOrPresetAndNothingRunsLong() {
        let c = HapticLibrary.count
        #expect(c.pattern(.left).beats.count == 2 && c.pattern(.right).beats.count == 3)
        let d = HapticLibrary.direction
        #expect(d.pattern(.left).beats.first?.kind == .directionDown && d.pattern(.right).beats.first?.kind == .directionUp)
        for set in HapticLibrary.all { for p in set.patterns { #expect(p.duration <= 2.0, "\(set.name) \(p.event): \(p.duration)s") } }
    }

    @Test func routeToolingHandlesTravelModeTuning() {
        #expect(TravelMode.walk.tuning.corridorRadius == 15)
        #expect(TravelMode.drive.tuning.corridorRadius == 30)
        #expect(TravelMode.cycle.profile == .cycling)
    }
}

struct WatchModeTests {
    @Test func watchOffersWalkRunCycleOnly() {
        #expect(TravelMode.watchModes == [.walk, .run, .cycle])
        #expect(TravelMode.drive.isSafeOnWatch == false)
        #expect(TravelMode.walk.isSafeOnWatch && TravelMode.run.isSafeOnWatch && TravelMode.cycle.isSafeOnWatch)
    }

    @Test func swipingStepsThroughTheModesAndWraps() {
        #expect(TravelMode.walk.onWatch(steps: 1) == .run)
        #expect(TravelMode.run.onWatch(steps: 1) == .cycle)
        #expect(TravelMode.cycle.onWatch(steps: 1) == .walk)
        #expect(TravelMode.walk.onWatch(steps: -1) == .cycle)
        #expect(TravelMode.cycle.onWatch(steps: -1) == .run)
        #expect(TravelMode.walk.onWatch(steps: 7) == .run)
    }

    @Test func drivingStepsToWalkRatherThanStaying() {
        #expect(TravelMode.drive.onWatch(steps: 1) == .walk)
        #expect(TravelMode.drive.onWatch(steps: -1) == .walk)
    }
}

struct RouteTrackerNextInstructionTests {
    private func step(_ type: String, along: Double, side: TurnSide = .straight) -> RouteStep {
        let p = CLLocationCoordinate2D(latitude: 0, longitude: along / 111_320)
        return RouteStep(id: UUID(), instruction: type, distance: 0, duration: 0, name: "", maneuverType: type, maneuverModifier: nil,
                         startCoordinate: p, endCoordinate: p, bearing: 90, intersections: [], startAlong: along, endAlong: along,
                         startIndex: 0, endIndex: 0, turn: TurnShape(side: side, severity: .normal), exitNumber: nil, exitBearing: 90)
    }

    @Test func passThroughStepsAreSkippedSoTheArrowIsAlwaysATurn() {
        let route = Route(
            geometry: (0...10).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 100 / 111_320) },
            distance: 1000, duration: 700,
            steps: [step("depart", along: 0), step("new name", along: 200), step("continue", along: 400),
                    step("turn", along: 600, side: .left), step("arrive", along: 1000)],
            segmentDurations: [], segmentSpeeds: [])
        var t = RouteTracker(route: route)
        let p = t.update(position: CLLocationCoordinate2D(latitude: 0, longitude: 50 / 111_320))
        #expect(p.nextTurn?.side == .left)
        #expect(abs(p.distanceToNext - 550) < 6, "distance is to the turn at 600 m, not the pass-through steps")
        #expect(p.nextStepIndex == 3)
    }

    @Test func aRoundaboutCountsEvenWhenItsExitIsStraight() {
        let route = Route(
            geometry: (0...10).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 100 / 111_320) },
            distance: 1000, duration: 700,
            steps: [step("depart", along: 0), step("roundabout", along: 300), step("arrive", along: 1000)],
            segmentDurations: [], segmentSpeeds: [])
        var t = RouteTracker(route: route)
        let p = t.update(position: CLLocationCoordinate2D(latitude: 0, longitude: 50 / 111_320))
        #expect(p.nextStepIndex == 1)
        #expect(abs(p.distanceToNext - 250) < 6)
    }
}

struct WatchSyncTests {
    @Test func theModeSurvivesTheRoundTrip() {
        for mode in TravelMode.allCases {
            #expect(WatchSync.mode(from: WatchSync.payload(mode: mode)) == mode)
        }
    }

    @Test func missingOrUnknownModesAreNil() {
        #expect(WatchSync.mode(from: [:]) == nil)
        #expect(WatchSync.mode(from: ["travelMode": "hover"]) == nil)
        #expect(WatchSync.mode(from: ["travelMode": 7]) == nil)
    }

    @Test func everyProfileHasAHost() {
        for p in TravelProfile.allCases { #expect(OSRMHosts.baseURL(for: p).hasPrefix("https://")) }
    }
}
