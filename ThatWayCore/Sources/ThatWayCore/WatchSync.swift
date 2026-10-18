//
//  WatchSync.swift
//  ThatWayCore
//
//  What the iPhone tells the watch, as plain dictionaries (the WatchConnectivity transport itself lives in each app).
//  Only the travel mode travels: no places, routes or coordinates. The watch uses it for one safety rule — if the
//  phone is in Drive mode the watch refuses to guide.
//

import Foundation

public enum WatchSync {
    public static let modeKey = "travelMode"

    public static func payload(mode: TravelMode) -> [String: Any] {
        [modeKey: mode.rawValue]
    }

    /// The travel mode in a received context/message, nil if it carries none (or an unknown value).
    public static func mode(from payload: [String: Any]) -> TravelMode? {
        (payload[modeKey] as? String).flatMap(TravelMode.init(rawValue:))
    }
}

/// Which OSRM host serves each routing profile. These are public demo hosts (not secrets); the iPhone app's `Config`
/// and the watch both read this table so there is one place to change when a production host is chosen.
public enum OSRMHosts {
    public static func baseURL(for profile: TravelProfile) -> String {
        switch profile {
        case .driving: return "https://routing.openstreetmap.de/routed-car/route/v1/driving"
        case .walking: return "https://routing.openstreetmap.de/routed-foot/route/v1/driving"
        case .cycling: return "https://routing.openstreetmap.de/routed-bike/route/v1/driving"
        }
    }
}
