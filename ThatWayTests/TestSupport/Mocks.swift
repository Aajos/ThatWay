//
//  Mocks.swift
//  ThatWayTests
//

import CoreLocation
@testable import ThatWay
import ThatWayCore

final class MockConnectivityMonitor: ConnectivityMonitoring {
    var isConnected: Bool
    var onChange: ((Bool) -> Void)?

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    func setConnected(_ connected: Bool) {
        isConnected = connected
        onChange?(connected)
    }
}

/// A `RoutingProvider` whose answer (or error) is scripted per call, for fallback-chain and
/// governor tests — never touches the network.
final class MockRoutingProvider: RoutingProvider {
    private var results: [Result<Route, Error>]
    private(set) var callCount = 0

    init(results: [Result<Route, Error>]) {
        self.results = results
    }

    convenience init(alwaysFailingWith error: RoutingError) {
        self.init(results: [.failure(error)])
    }

    convenience init(alwaysSucceedingWith route: Route) {
        self.init(results: [.success(route)])
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route {
        callCount += 1
        let index = min(callCount - 1, results.count - 1)
        return try results[index].get()
    }
}

enum TestRoutes {
    static let trivial = Route(
        geometry: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
        ],
        distance: 111,
        duration: 20,
        steps: [],
        segmentDurations: [],
        segmentSpeeds: []
    )
}
