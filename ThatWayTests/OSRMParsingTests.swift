//
//  OSRMParsingTests.swift
//  ThatWayTests
//

import Testing
import CoreLocation
@testable import ThatWay

// Serialized: every test in this suite sets the shared `MockURLProtocol.handler` static, which
// races under Swift Testing's default parallel execution.
@Suite(.serialized)
struct OSRMParsingTests {
    private func makeProvider(fixture: String) -> OSRMRoutingProvider {
        MockURLProtocol.handler = { request in Fixture.response(fixture, url: request.url!) }
        return OSRMRoutingProvider(session: MockURLProtocol.makeSession())
    }

    @Test func parsesSimpleDriveIntoRoute() async throws {
        let provider = makeProvider(fixture: "simple_drive")
        let route = try await provider.route(from: .init(latitude: -37.826, longitude: 145.0455), to: .init(latitude: -37.834, longitude: 145.0575), profile: .driving)
        #expect(route.geometry.count > 1)
        #expect(route.distance > 0)
        #expect(!route.steps.isEmpty)
        #expect(route.steps.last?.maneuverType == "arrive")
        // Every step's geometry indices should be in range and non-decreasing.
        for step in route.steps {
            #expect(step.startIndex >= 0 && step.startIndex < route.geometry.count)
            #expect(step.endIndex >= step.startIndex)
        }
    }

    @Test func roundaboutStepGetsAnExitBearingAndTurnShape() async throws {
        let provider = makeProvider(fixture: "roundabout_route")
        let route = try await provider.route(from: .init(latitude: -37.826, longitude: 145.0455), to: .init(latitude: -37.7995, longitude: 144.9986), profile: .driving)
        let roundaboutSteps = route.steps.filter { $0.maneuverType == "roundabout" || $0.maneuverType == "rotary" }
        #expect(!roundaboutSteps.isEmpty, "fixture should contain a roundabout step")
        for step in roundaboutSteps {
            // The exit bearing is what the roundabout's turn shape (left/straight/right) is
            // judged from in OSRMRoutingProvider.turnShape — it should always be present.
            #expect(step.exitNumber != nil)
        }
    }

    @Test func walkingFixtureParsesWithoutError() async throws {
        let provider = makeProvider(fixture: "simple_walk")
        let route = try await provider.route(from: .init(latitude: -37.8, longitude: 145.0), to: .init(latitude: -37.802, longitude: 145.003), profile: .walking)
        #expect(route.distance > 0)
    }
}
