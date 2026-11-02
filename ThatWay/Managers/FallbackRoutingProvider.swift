//
//  FallbackRoutingProvider.swift
//  ThatWay
//
//  Tries a list of providers in order, moving to the next only when the failure looks like
//  "this host is having a bad time" rather than "this request has no answer". Holds a single
//  OSRM provider today; the seam exists so a second engine can be added later with no other
//  code change.
//

import CoreLocation
import ThatWayCore

final class FallbackRoutingProvider: RoutingProvider {
    private let providers: [RoutingProvider]

    init(providers: [RoutingProvider]) {
        self.providers = providers
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route {
        guard !providers.isEmpty else { throw RoutingError.invalidResponse }
        var lastError: Error = RoutingError.invalidResponse
        for provider in providers {
            do {
                return try await provider.route(from: origin, to: destination, profile: profile)
            } catch let error as RoutingError {
                lastError = error
                switch error {
                case .network, .timeout, .serverError, .rateLimited:
                    continue // this host is struggling — worth trying the next one
                case .noRoute, .noRoadNearby, .invalidResponse:
                    throw error // a different host won't change the answer to this question
                }
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }
}
