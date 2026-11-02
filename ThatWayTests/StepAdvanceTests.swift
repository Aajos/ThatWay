//
//  StepAdvanceTests.swift
//  ThatWayTests
//
//  Regression coverage for the progress-tracking math `RoutingManager.advanceProgress` does on
//  every location update: it must never let progress (or the current step) jump backward, even
//  when fed a noisy or out-of-order sequence of positions.
//

import Testing
import CoreLocation
@testable import ThatWay
import ThatWayCore

@MainActor
struct StepAdvanceTests {
    @Test func progressNeverGoesBackwardAlongASimpleRoute() async throws {
        let route = Route(
            geometry: (0...20).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) },
            distance: 2000, duration: 200,
            steps: [
                RouteStep(id: UUID(), instruction: "Head out", distance: 1000, duration: 100, name: "A St",
                          maneuverType: "depart", maneuverModifier: nil,
                          startCoordinate: .init(latitude: 0, longitude: 0), endCoordinate: .init(latitude: 0, longitude: 0.010),
                          bearing: 90, intersections: [], startAlong: 0, endAlong: 1000, startIndex: 0, endIndex: 10,
                          turn: .straight, exitNumber: nil, exitBearing: 90),
                RouteStep(id: UUID(), instruction: "Arrive", distance: 0, duration: 0, name: "",
                          maneuverType: "arrive", maneuverModifier: nil,
                          startCoordinate: .init(latitude: 0, longitude: 0.020), endCoordinate: .init(latitude: 0, longitude: 0.020),
                          bearing: 90, intersections: [], startAlong: 2000, endAlong: 2000, startIndex: 20, endIndex: 20,
                          turn: .straight, exitNumber: nil, exitBearing: nil),
            ],
            segmentDurations: [], segmentSpeeds: []
        )
        let manager = RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: route))
        await manager.getRoute(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 0, longitude: 0.020), profile: .driving)
        #expect(manager.hasRoute)

        var lastProgress: Double = -1
        // A realistic noisy sequence: mostly forward, with small backward jitters a real GPS
        // fix produces when stationary or slow — progress must still be monotonic.
        let noisyLongitudes: [Double] = [0.001, 0.002, 0.0019, 0.003, 0.004, 0.0038, 0.005, 0.008, 0.012, 0.0119, 0.016, 0.019]
        for lon in noisyLongitudes {
            manager.advanceProgress(userLocation: .init(latitude: 0, longitude: lon))
            #expect(manager.progressAlong >= lastProgress, "progress went backward at lon \(lon)")
            lastProgress = manager.progressAlong
        }
    }
}
