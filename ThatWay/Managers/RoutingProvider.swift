//
//  RoutingProvider.swift
//  ThatWay
//
//  The seam the whole routing stack is built behind — swapping the engine later means writing
//  one new type conforming to this protocol and pointing `Config` at it, nothing else.
//

import CoreLocation

/// Driving, walking or cycling — each resolves to its own base URL in `Config`, and each
/// carries whether that URL has actually been verified to serve a genuinely distinct profile
/// rather than silently returning driving data under another name (see `Config.swift`).
enum TravelProfile: String, CaseIterable {
    case driving, walking, cycling

    var displayName: String {
        switch self {
        case .driving: return "driving"
        case .walking: return "walking"
        case .cycling: return "cycling"
        }
    }

    var baseURL: String { Config.osrmBaseURL(for: self) }
    /// False means: don't trust this profile's results until a real host for it is configured —
    /// see `Config.profileVerified`.
    var servesProfileGenuinely: Bool { Config.profileVerified(self) }
}

/// Every error a `RoutingProvider` can throw. `noRoute` and `noRoadNearby` are kept distinct
/// (OSRM's own `NoRoute` vs `NoSegment` codes) because they produce different diagnoses to the
/// traveller: "no path connects these two points" versus "there's no road here at all".
enum RoutingError: Error, Equatable {
    case network
    case timeout
    case noRoute
    case noRoadNearby
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case invalidResponse
}

protocol RoutingProvider {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route
}
