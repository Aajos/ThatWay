//
//  RoutingProvider.swift
//  ThatWay
//
//  The routing seam itself (`RoutingProvider`, `RoutingError`, the OSRM implementation) lives in ThatWayCore so the
//  watch can use it. What stays here is the app's own configuration: which URL serves which profile.
//

import CoreLocation
import ThatWayCore

extension TravelProfile {
    var baseURL: String { Config.osrmBaseURL(for: self) }
    /// False means: don't trust this profile's results until a real host for it is configured —
    /// see `Config.profileVerified`.
    var servesProfileGenuinely: Bool { Config.profileVerified(self) }
}

extension OSRMRoutingProvider {
    /// The provider configured the way the iPhone app wants it (hosts and user agent from `Config`).
    static func app(session: URLSession? = nil) -> OSRMRoutingProvider {
        OSRMRoutingProvider(baseURL: { Config.osrmBaseURL(for: $0) }, userAgent: Config.userAgent, session: session)
    }
}
