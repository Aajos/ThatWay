//
//  RoutePersistence.swift
//  ThatWay
//
//  Keeps the active trip alive across a relaunch — save while guiding, restore once at launch,
//  delete the moment navigation ends (either way) so a stale trip never reappears later.
//

import CoreLocation
import Foundation
import ThatWayCore

struct PersistedTrip: Codable {
    let route: Route
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationName: String
    let profile: TravelProfile
}

extension TravelProfile: Codable {}

enum RoutePersistence {
    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("active-trip.json")
    }

    static func save(_ trip: PersistedTrip) {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(trip)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[RoutePersistence] Failed to save active trip: \(error.localizedDescription)")
        }
    }

    static func load() -> PersistedTrip? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedTrip.self, from: data)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
