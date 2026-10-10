//
//  TravelModeTests.swift
//  ThatWayTests
//

import Testing
import Foundation
import CoreLocation
@testable import ThatWay
import ThatWayCore

@MainActor
@Suite(.serialized)
struct TravelModeTests {
    @Test func modeMapsToRoutingProfile() {
        #expect(TravelMode.walk.profile == .walking)
        #expect(TravelMode.run.profile == .walking)
        #expect(TravelMode.cycle.profile == .cycling)
        #expect(TravelMode.drive.profile == .driving)
    }

    @Test func drivingTuningKeepsPreviousValues() {
        let t = TravelMode.drive.tuning
        #expect(t.corridorRadius == 30)
        #expect(t.pollInterval == 3)
        #expect(t.polylineRevealDistance == 500)
        #expect(t.farCutoff == 1000)
        #expect(t.hardTiltEngageDistance == 1000)
        #expect(t.arrivalRadius == 5)
        #expect(t.startSnapRadius == 50)
        #expect(t.tier2MinSpacing == 60)
        #expect(TravelMode.walk.tuning.corridorRadius == 15)
        #expect(TravelMode.walk.tuning.pollInterval == 10)
        #expect(TravelMode.walk.tuning.tier2MinSpacing == 40)
    }

    @Test func selectionPersistsAcrossLaunch() {
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
        let first = AppModel(routingManager: RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)))
        #expect(first.travelMode == .walk)
        first.travelMode = .cycle
        let second = AppModel(routingManager: RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)))
        #expect(second.travelMode == .cycle)
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
    }

    @Test func rapidModeChangesProduceOneReroute() async throws {
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
        let provider = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let app = AppModel(routingManager: RoutingManager(provider: provider))
        app.modeChangeDebounce = .milliseconds(80)
        app.destinationCoordinate = .init(latitude: 0, longitude: 0.001)
        app.mode = .guidance

        for mode in [TravelMode.run, .cycle, .drive, .cycle, .walk, .drive] {
            app.travelMode = mode
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(provider.callCount == 1)
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
    }

    @Test func modeChangeInPointModeOnlyStoresTheSelection() async throws {
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
        let provider = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let app = AppModel(routingManager: RoutingManager(provider: provider))
        app.modeChangeDebounce = .milliseconds(30)
        app.destinationCoordinate = .init(latitude: 0, longitude: 0.001)
        app.mode = .point
        app.travelMode = .drive
        try await Task.sleep(for: .milliseconds(200))
        #expect(provider.callCount == 0)
        UserDefaults.standard.removeObject(forKey: "travelMode.v1")
    }

    @Test func modeChangeRerouteIsNotBlockedByRerouteCooldown() async throws {
        let provider = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let manager = RoutingManager(provider: provider)
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        await manager.getRoute(from: a, to: b, profile: .driving, isReroute: true)   // starts the 15s cooldown
        await manager.getRoute(from: a, to: b, profile: .walking, isReroute: false)  // a mode change: initial path
        #expect(provider.callCount == 2)
    }

    @Test func failedModeChangeKeepsTheOldRouteAndShowsDiagnosis() async throws {
        let ok = TestRoutes.trivial
        let provider = MockRoutingProvider(results: [.success(ok), .failure(RoutingError.noRoute)])
        let manager = RoutingManager(provider: provider)
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        await manager.getRoute(from: a, to: b, profile: .driving)
        let before = manager.routePolyline.count
        await manager.getRoute(from: a, to: b, profile: .walking)
        try await Task.sleep(for: .milliseconds(50)) // the failure is mirrored to the manager via Combine on the main queue
        #expect(before > 1)
        #expect(manager.routePolyline.count == before)
        #expect(manager.currentFailure == .noRoute(mode: "walking"))
    }
}

/// Suspends until its task is cancelled, then throws the way URLSession does.
private final class HangingProvider: RoutingProvider {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        throw CancellationError()
    }
}

@MainActor
struct CancelledRequestTests {
    @Test func cancelledRequestNeverShowsAnError() async throws {
        let governor = RoutingGovernor(provider: HangingProvider(), connectivity: MockConnectivityMonitor())
        let task = Task {
            await governor.fetchInitial(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 0, longitude: 0.001), profile: .walking)
        }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()
        let result = await task.value
        #expect(result == nil)
        #expect(governor.currentFailure == nil)
    }
}
