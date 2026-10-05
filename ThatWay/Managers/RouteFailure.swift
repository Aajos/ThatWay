//
//  RouteFailure.swift
//  ThatWay
//
//  The plain-language diagnosis shown to the traveller, built from a `RoutingError` plus
//  whatever else is needed to tell the cases apart that `RoutingError` alone can't (offline vs.
//  a struggling server look identical as `.network` until you ask the connectivity monitor).
//

import Foundation

enum RouteFailure: Equatable {
    case offline
    case timeout
    case serverUnavailable
    case rateLimited
    case noRoute(mode: String)
    case noRoadNearby
    case locationUnavailable

    /// Short stable name for the test log (no details).
    var logName: String {
        switch self {
        case .offline: return "offline"
        case .timeout: return "timeout"
        case .serverUnavailable: return "serverUnavailable"
        case .rateLimited: return "rateLimited"
        case .noRoute: return "noRoute"
        case .noRoadNearby: return "noRoadNearby"
        case .locationUnavailable: return "locationUnavailable"
        }
    }

    var message: String {
        switch self {
        case .offline: return "No internet connection. Waiting to reconnect."
        case .timeout: return "Routing service isn't responding. Retrying."
        case .serverUnavailable: return "Routing service isn't responding. Retrying."
        case .rateLimited: return "Routing service is busy. Retrying shortly."
        case .noRoute(let mode): return "No \(mode) route found to this destination."
        case .noRoadNearby: return "Couldn't find a road or path near your location or the destination."
        case .locationUnavailable: return "Waiting for a GPS fix."
        }
    }

    /// Retryable failures keep the governor's backoff loop running; these two stop it —
    /// nothing about retrying the same request again would change the answer.
    var isRetryable: Bool {
        switch self {
        case .noRoute, .noRoadNearby: return false
        case .offline, .timeout, .serverUnavailable, .rateLimited, .locationUnavailable: return true
        }
    }

    static func from(_ error: RoutingError, profile: TravelProfile, isConnected: Bool) -> RouteFailure {
        switch error {
        case .network: return isConnected ? .serverUnavailable : .offline
        case .timeout: return .timeout
        case .serverError: return .serverUnavailable
        case .rateLimited: return .rateLimited
        case .noRoute: return .noRoute(mode: profile.displayName)
        case .noRoadNearby: return .noRoadNearby
        case .invalidResponse: return .serverUnavailable
        }
    }
}
