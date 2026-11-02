//
//  RoutePlausibility.swift
//  ThatWayCore
//
//  A cheap check that runs BEFORE any routing request: is this even worth asking a road router about? A destination on
//  another continent (or just absurdly far for how the person is travelling) can never have a useful turn-by-turn route,
//  and asking anyway costs a slow request, hammers a shared routing server, and can leave the app "retrying" for ever.
//  When the answer is "too far", the compass simply keeps pointing straight at it (great-circle bearing, any range).
//
//  This is a distance rule, not a map: it cannot know that two nearby places are separated by water or have no road
//  between them. Those come back from the router as "no route" / "no road nearby", which stop at once (no retry).
//

import Foundation
import CoreLocation

public enum RoutePlausibility: Equatable, Sendable {
    case routable
    case tooFar(limitKm: Double)

    /// The furthest, in straight-line kilometres, that a road route is worth asking for, by how you are travelling.
    /// Generous on purpose: Melbourne to Perth by road is about 3,400 km.
    public static func limitKm(for profile: TravelProfile) -> Double {
        switch profile {
        case .walking: return 200
        case .cycling: return 800
        case .driving: return 4_500
        }
    }

    public static func check(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) -> RoutePlausibility {
        let km = CompassManager.distance(from: origin, to: destination) / 1000
        let limit = limitKm(for: profile)
        return km > limit ? .tooFar(limitKm: limit) : .routable
    }
}
