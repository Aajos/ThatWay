//
//  RoutingProvider.swift
//  ThatWayCore
//
//  The seam the whole routing stack is built behind — swapping the engine later means writing
//  one new type conforming to this protocol and pointing the app's `Config` at it, nothing else.
//  Shared with the watch, which fetches its own routes.
//

import CoreLocation
import Foundation

/// Every error a `RoutingProvider` can throw. `noRoute` and `noRoadNearby` are kept distinct
/// (OSRM's own `NoRoute` vs `NoSegment` codes) because they produce different diagnoses to the
/// traveller: "no path connects these two points" versus "there's no road here at all".
public enum RoutingError: Error, Equatable {
    case network
    case timeout
    case noRoute
    case noRoadNearby
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case invalidResponse
}

public protocol RoutingProvider {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route
}
