//
//  RoutingErrorMappingTests.swift
//  ThatWayTests
//
//  An extension of `OSRMParsingTests` (not a separate `@Suite`) on purpose — both share the
//  `MockURLProtocol.handler` static, and Swift Testing's `.serialized` trait only guarantees
//  mutual exclusion *within* one suite, not across two. Keeping every test that touches the
//  mock handler in a single serialized suite is what actually prevents the race.
//

import Testing
import CoreLocation
@testable import ThatWay
import ThatWayCore

extension OSRMParsingTests {
    private func provider(statusCode: Int, fixture: String, headers: [String: String] = [:]) -> OSRMRoutingProvider {
        MockURLProtocol.handler = { request in Fixture.response(fixture, url: request.url!, statusCode: statusCode, headers: headers) }
        return OSRMRoutingProvider.app(session: MockURLProtocol.makeSession())
    }

    @Test func noRouteCodeMapsToNoRouteError() async throws {
        let p = provider(statusCode: 200, fixture: "no_route")
        do {
            _ = try await p.route(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 1, longitude: 1), profile: .driving)
            Issue.record("expected noRoute to be thrown")
        } catch {
            #expect(error as? RoutingError == .noRoute)
        }
    }

    @Test func noSegmentCodeMapsToNoRoadNearbyError() async throws {
        let p = provider(statusCode: 200, fixture: "no_segment")
        do {
            _ = try await p.route(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 1, longitude: 1), profile: .driving)
            Issue.record("expected noRoadNearby to be thrown")
        } catch {
            #expect(error as? RoutingError == .noRoadNearby)
        }
    }

    @Test func http429MapsToRateLimitedWithRetryAfter() async throws {
        let p = provider(statusCode: 429, fixture: "no_route", headers: ["Retry-After": "7"])
        do {
            _ = try await p.route(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 1, longitude: 1), profile: .driving)
            Issue.record("expected rateLimited to be thrown")
        } catch RoutingError.rateLimited(let retryAfter) {
            #expect(retryAfter == 7)
        }
    }

    @Test func http5xxMapsToServerError() async throws {
        let p = provider(statusCode: 503, fixture: "no_route")
        do {
            _ = try await p.route(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 1, longitude: 1), profile: .driving)
            Issue.record("expected serverError to be thrown")
        } catch {
            #expect(error as? RoutingError == .serverError(503))
        }
    }

    @Test func malformedBodyMapsToInvalidResponse() async throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "not json".data(using: .utf8)!)
        }
        let p = OSRMRoutingProvider.app(session: MockURLProtocol.makeSession())
        do {
            _ = try await p.route(from: .init(latitude: 0, longitude: 0), to: .init(latitude: 1, longitude: 1), profile: .driving)
            Issue.record("expected invalidResponse to be thrown")
        } catch {
            #expect(error as? RoutingError == .invalidResponse)
        }
    }

    // MARK: RouteFailure.from

    @Test func networkErrorBecomesOfflineWhenDisconnected() {
        let failure = RouteFailure.from(.network, profile: .driving, isConnected: false)
        #expect(failure == .offline)
    }

    @Test func networkErrorBecomesServerUnavailableWhenConnected() {
        let failure = RouteFailure.from(.network, profile: .driving, isConnected: true)
        #expect(failure == .serverUnavailable)
    }

    @Test func noRouteCarriesProfileDisplayName() {
        let failure = RouteFailure.from(.noRoute, profile: .walking, isConnected: true)
        #expect(failure == .noRoute(mode: "walking"))
        #expect(failure.message.contains("walking"))
    }

    @Test func nonRetryableFailuresDontRetry() {
        #expect(RouteFailure.noRoute(mode: "driving").isRetryable == false)
        #expect(RouteFailure.noRoadNearby.isRetryable == false)
        #expect(RouteFailure.offline.isRetryable == true)
        #expect(RouteFailure.rateLimited.isRetryable == true)
    }
}
