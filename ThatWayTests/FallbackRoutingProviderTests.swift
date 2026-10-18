//
//  FallbackRoutingProviderTests.swift
//  ThatWayTests
//

import Testing
import CoreLocation
@testable import ThatWay
import ThatWayCore

struct FallbackRoutingProviderTests {
    private let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private let destination = CLLocationCoordinate2D(latitude: 1, longitude: 1)

    @Test func advancesToNextProviderOnNetworkFailure() async throws {
        let first = MockRoutingProvider(alwaysFailingWith: .network)
        let second = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let chain = FallbackRoutingProvider(providers: [first, second])
        let route = try await chain.route(from: origin, to: destination, profile: .driving)
        #expect(route.distance == TestRoutes.trivial.distance)
        #expect(first.callCount == 1)
        #expect(second.callCount == 1)
    }

    @Test func doesNotAdvanceOnNoRoute() async throws {
        let first = MockRoutingProvider(alwaysFailingWith: .noRoute)
        let second = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let chain = FallbackRoutingProvider(providers: [first, second])
        do {
            _ = try await chain.route(from: origin, to: destination, profile: .driving)
            Issue.record("expected noRoute to propagate without trying the second provider")
        } catch {
            #expect(error as? RoutingError == .noRoute)
        }
        #expect(second.callCount == 0)
    }

    @Test func doesNotAdvanceOnNoRoadNearby() async throws {
        let first = MockRoutingProvider(alwaysFailingWith: .noRoadNearby)
        let second = MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)
        let chain = FallbackRoutingProvider(providers: [first, second])
        do {
            _ = try await chain.route(from: origin, to: destination, profile: .driving)
            Issue.record("expected noRoadNearby to propagate")
        } catch {
            #expect(error as? RoutingError == .noRoadNearby)
        }
        #expect(second.callCount == 0)
    }

    @Test func throwsLastErrorWhenEveryProviderFails() async throws {
        let first = MockRoutingProvider(alwaysFailingWith: .timeout)
        let second = MockRoutingProvider(alwaysFailingWith: .serverError(500))
        let chain = FallbackRoutingProvider(providers: [first, second])
        do {
            _ = try await chain.route(from: origin, to: destination, profile: .driving)
            Issue.record("expected the chain to exhaust and throw")
        } catch {
            #expect(error as? RoutingError == .serverError(500))
        }
    }
}
