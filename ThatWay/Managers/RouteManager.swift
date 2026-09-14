//
//  RouteManager.swift
//  ThatWay
//
//  Fetches turn-by-turn routes from MapKit and tracks progress through them.
//

import Combine
import CoreLocation
import MapKit

@MainActor
final class RouteManager: ObservableObject {
    @Published private(set) var route: MKRoute?
    @Published private(set) var steps: [MKRoute.Step] = []
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var isCalculating = false
    @Published var errorMessage: String?

    /// How close (metres) the user needs to get to a step's endpoint before we advance to the next one.
    private let stepArrivalRadius: CLLocationDistance = 30

    var currentStep: MKRoute.Step? {
        steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil
    }

    var nextStep: MKRoute.Step? {
        let next = currentStepIndex + 1
        return steps.indices.contains(next) ? steps[next] : nil
    }

    var isFinished: Bool { !steps.isEmpty && currentStepIndex >= steps.count - 1 }

    func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType = .automobile
    ) async {
        isCalculating = true
        errorMessage = nil
        defer { isCalculating = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else {
                errorMessage = "No route found."
                return
            }
            route = best
            steps = best.steps.filter { !$0.instructions.isEmpty }
            currentStepIndex = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        route = nil
        steps = []
        currentStepIndex = 0
        errorMessage = nil
    }

    /// Advances `currentStepIndex` once the user gets near the end of the current step,
    /// mirroring how turn-by-turn guidance moves on to the next instruction.
    func updateProgress(userLocation: CLLocation) {
        guard let step = currentStep, !isFinished else { return }
        guard let end = step.polyline.lastCoordinate else { return }
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        if userLocation.distance(from: endLocation) <= stepArrivalRadius {
            currentStepIndex += 1
        }
    }
}

private extension MKPolyline {
    var lastCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.last
    }
}
