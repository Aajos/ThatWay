//
//  PlaceSearch.swift
//  ThatWay
//
//  Real place lookups via MapKit's local search — resolves a searched name to an actual
//  coordinate, and finds actual nearby points of interest, instead of relying on a fixed
//  lookup table. Free, no API key: comes with MapKit.
//

import CoreLocation
import MapKit

enum PlaceSearch {
    /// What a live search came back with. "Nothing matches" and "the search itself failed" are different things to tell someone.
    enum Outcome {
        case found([MKMapItem])
        case noMatches
        case failed
    }

    /// MapKit reports an empty result as an error (placemarkNotFound), not as an empty list; every other error is a failure.
    static func isNoMatch(_ error: Error) -> Bool { (error as? MKError)?.code == .placemarkNotFound }

    /// Resolves `query` to a real coordinate, preferring results near `coordinate`.
    /// Returns the top match, or nil if the search fails or turns up nothing.
    static func firstResult(for query: String, near coordinate: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        print("[PlaceSearch] Searching")
        do {
            let response = try await MKLocalSearch(request: request).start()
            print("[PlaceSearch] \(response.mapItems.count) result(s)")
            return response.mapItems.first?.placemark.coordinate
        } catch {
            print("[PlaceSearch] failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Searches for `query` and returns up to `limit` matches, nearest-first, for a live
    /// search dropdown — real relevance-ranked results from MapKit, re-sorted by actual
    /// distance from `coordinate` so the closest matching places surface first.
    static func search(for query: String, near coordinate: CLLocationCoordinate2D, limit: Int = 10) async -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .noMatches }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        print("[PlaceSearch] Searching top \(limit)")
        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = response.mapItems.sorted { lhs, rhs in
                let lhsLoc = CLLocation(latitude: lhs.placemark.coordinate.latitude, longitude: lhs.placemark.coordinate.longitude)
                let rhsLoc = CLLocation(latitude: rhs.placemark.coordinate.latitude, longitude: rhs.placemark.coordinate.longitude)
                return origin.distance(from: lhsLoc) < origin.distance(from: rhsLoc)
            }
            let top = Array(nearest.prefix(limit))
            print("[PlaceSearch] kept \(top.count) of \(response.mapItems.count) result(s)")
            return top.isEmpty ? .noMatches : .found(top)
        } catch {
            print("[PlaceSearch] failed: \(error.localizedDescription)")
            return isNoMatch(error) ? .noMatches : .failed
        }
    }
}
