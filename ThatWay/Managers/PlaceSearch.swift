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
    /// Resolves `query` to a real coordinate, preferring results near `coordinate`.
    /// Returns the top match, or nil if the search fails or turns up nothing.
    static func firstResult(for query: String, near coordinate: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        print("[PlaceSearch] Searching for \"\(query)\" near \(coordinate.latitude), \(coordinate.longitude)")
        do {
            let response = try await MKLocalSearch(request: request).start()
            print("[PlaceSearch] \"\(query)\" -> \(response.mapItems.count) result(s)")
            return response.mapItems.first?.placemark.coordinate
        } catch {
            print("[PlaceSearch] \"\(query)\" failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Searches for `query` and returns up to `limit` matches, nearest-first, for a live
    /// search dropdown — real relevance-ranked results from MapKit, re-sorted by actual
    /// distance from `coordinate` so the closest matching places surface first.
    static func search(for query: String, near coordinate: CLLocationCoordinate2D, limit: Int = 10) async -> [MKMapItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        print("[PlaceSearch] Searching top \(limit) for \"\(trimmed)\" near \(coordinate.latitude), \(coordinate.longitude)")
        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = response.mapItems.sorted { lhs, rhs in
                let lhsLoc = CLLocation(latitude: lhs.placemark.coordinate.latitude, longitude: lhs.placemark.coordinate.longitude)
                let rhsLoc = CLLocation(latitude: rhs.placemark.coordinate.latitude, longitude: rhs.placemark.coordinate.longitude)
                return origin.distance(from: lhsLoc) < origin.distance(from: rhsLoc)
            }
            let top = Array(nearest.prefix(limit))
            print("[PlaceSearch] \"\(trimmed)\" -> kept \(top.count) of \(response.mapItems.count) result(s)")
            return top
        } catch {
            print("[PlaceSearch] \"\(trimmed)\" failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Real points of interest within `radius` metres of `coordinate` — cafes, shops,
    /// landmarks, etc. — for the map's "what's around here" layer.
    static func nearbyPlaces(around coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [MKMapItem] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        print("[PlaceSearch] Fetching nearby places within \(Int(radius))m of \(coordinate.latitude), \(coordinate.longitude)")
        do {
            let response = try await MKLocalSearch(request: request).start()
            print("[PlaceSearch] Found \(response.mapItems.count) nearby place(s)")
            return response.mapItems
        } catch {
            print("[PlaceSearch] Nearby places failed: \(error.localizedDescription)")
            return []
        }
    }
}
