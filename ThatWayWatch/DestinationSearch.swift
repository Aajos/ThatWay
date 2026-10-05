//
//  DestinationSearch.swift
//  ThatWayWatch
//
//  Looks up a spoken place name with MapKit, near the wearer. Results live in memory for the search screen only:
//  nothing here is stored or logged (no queries, names or coordinates).
//

import Foundation
import MapKit
import CoreLocation

@MainActor
final class DestinationSearch: ObservableObject {
    struct Place: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let coordinate: CLLocationCoordinate2D
        let distance: CLLocationDistance?
    }
    enum State { case idle, searching, empty, failed }

    @Published private(set) var places: [Place] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var heard = ""

    func reset() { places = []; state = .idle; heard = "" }

    func search(_ text: String, near fix: CLLocation?) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        heard = query
        state = .searching
        places = []
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let fix { request.region = MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 8000, longitudinalMeters: 8000) }
        do {
            let response = try await MKLocalSearch(request: request).start()
            let found: [Place] = response.mapItems.prefix(8).compactMap { item in
                let c = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(c), let name = item.name else { return nil }
                let detail = [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
                let d = fix.map { CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: $0) }
                return Place(name: name, detail: detail, coordinate: c, distance: d)
            }
            places = found.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
            state = places.isEmpty ? .empty : .idle
        } catch {
            state = .failed
        }
    }
}
