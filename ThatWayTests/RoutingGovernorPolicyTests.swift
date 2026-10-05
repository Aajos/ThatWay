//
//  RoutingGovernorPolicyTests.swift
//  ThatWayTests
//
//  Exercises the governor's pure scheduling math (backoff schedule, reroute cooldown/cap)
//  directly against an injected clock — no real sleeping, no flaky timing.
//

import Testing
import Foundation
import CoreLocation
@testable import ThatWay

@MainActor
struct RoutingGovernorPolicyTests {
    private func makeGovernor(now: @escaping () -> Date) -> RoutingGovernor {
        RoutingGovernor(
            provider: MockRoutingProvider(alwaysFailingWith: .network),
            connectivity: MockConnectivityMonitor(),
            now: now,
            randomJitter: { 0 } // deterministic: no jitter
        )
    }

    @Test func backoffFollowsTheCappedSchedule() {
        let governor = makeGovernor(now: Date.init)
        let expected: [TimeInterval] = [2, 4, 8, 16, 30, 30, 30] // holds at the last value
        for (attempt, delay) in expected.enumerated() {
            #expect(governor.backoffDelay(attempt: attempt, retryAfter: nil) == delay)
        }
    }

    @Test func retryAfterOverridesTheSchedule() {
        let governor = makeGovernor(now: Date.init)
        #expect(governor.backoffDelay(attempt: 0, retryAfter: 12) == 12)
        #expect(governor.backoffDelay(attempt: 4, retryAfter: 3) == 3)
    }

    @Test func rerouteCooldownBlocksAnImmediateSecondAttempt() async {
        var now = Date(timeIntervalSince1970: 0)
        let provider = MockRoutingProvider(alwaysFailingWith: .noRoute) // non-retryable: one shot, no backoff loop
        let governor = RoutingGovernor(provider: provider, connectivity: MockConnectivityMonitor(), now: { now })
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let destination = CLLocationCoordinate2D(latitude: 1, longitude: 1)

        _ = await governor.fetchReroute(from: origin, to: destination, profile: .driving) // records a timestamp at t=0
        now = now.addingTimeInterval(5) // well inside the 15s cooldown
        let blocked = await governor.fetchReroute(from: origin, to: destination, profile: .driving)
        #expect(blocked == nil)
        #expect(provider.callCount == 1, "the second call should never reach the provider at all")

        now = now.addingTimeInterval(20) // now past the cooldown
        _ = await governor.fetchReroute(from: origin, to: destination, profile: .driving)
        #expect(provider.callCount == 2)
    }

    @Test func rerouteCapStopsAFifthAttemptWithinTheWindow() async {
        var now = Date(timeIntervalSince1970: 0)
        let provider = MockRoutingProvider(alwaysFailingWith: .noRoute) // non-retryable: one shot per call
        let governor = RoutingGovernor(provider: provider, connectivity: MockConnectivityMonitor(), now: { now })
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let destination = CLLocationCoordinate2D(latitude: 1, longitude: 1)

        for i in 0..<4 {
            now = now.addingTimeInterval(Double(i) * 20) // well past the 15s cooldown each time
            _ = await governor.fetchReroute(from: origin, to: destination, profile: .driving)
        }
        now = now.addingTimeInterval(100)
        let result = await governor.fetchReroute(from: origin, to: destination, profile: .driving)
        #expect(result == nil)
        #expect(governor.currentFailure == .rateLimited, "a 5th reroute inside the 5-minute window should be governor-blocked, not even attempted")
    }
}
