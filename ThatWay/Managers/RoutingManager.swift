//
//  RoutingManager.swift
//  ThatWay
//
//  Fetches turn-by-turn routes from the free OSRM demo API (router.project-osrm.org)
//  and tracks progress through them. OSRM's public server is rate-limited and meant
//  for evaluation only — fine for this app's simulated navigation, not for
//  production traffic at scale.
//

import Combine
import CoreLocation
import Foundation

/// One turn-by-turn instruction: what to say, how far it covers, and the bearing to
/// walk/drive along for its own segment (from where the step starts to where it ends).
struct RouteStep: Identifiable {
    let id = UUID()
    let instruction: String
    let distance: CLLocationDistance
    let duration: TimeInterval
    let name: String
    let maneuverType: String
    let maneuverModifier: String?
    /// Where this step's own road segment begins and ends — used to compute `bearing`,
    /// and (for `endCoordinate`) to detect arrival at the step via `updateStepIfNeeded`.
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    /// The heading to point the compass along for this step, computed from
    /// `startCoordinate` to `endCoordinate` via `CompassManager.bearing`.
    let bearing: CLLocationDirection

    /// A rough left/right/straight bucket for the turn-arrow glyph, derived from OSRM's
    /// maneuver modifier (e.g. "slight left", "sharp right", "straight").
    var turnDirection: TurnDir {
        guard let modifier = maneuverModifier else { return .straight }
        if modifier.contains("left") { return .left }
        if modifier.contains("right") { return .right }
        return .straight
    }
}

@MainActor
final class RoutingManager: ObservableObject {
    @Published private(set) var steps: [RouteStep] = []
    @Published private(set) var routePolyline: [CLLocationCoordinate2D] = []
    @Published var currentStepIndex = 0
    @Published private(set) var totalDistance: Double = 0
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// How close (metres) the traveller needs to get to a step's endpoint before
    /// guidance advances to the next instruction.
    private let arrivalRadius: CLLocationDistance = 50

    var currentStep: RouteStep? { steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil }
    var nextStep: RouteStep? { steps.indices.contains(currentStepIndex + 1) ? steps[currentStepIndex + 1] : nil }
    var isFinished: Bool { !steps.isEmpty && currentStepIndex >= steps.count - 1 }
    var hasRoute: Bool { !steps.isEmpty }

    /// Fetches a driving route from OSRM and populates `steps`, `routePolyline`,
    /// `totalDistance`, and `totalDuration`. Logs the request and outcome for debugging.
    func getRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // OSRM takes coordinates as "lon,lat" — the opposite order from CLLocationCoordinate2D.
        let coordinatePath = "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
        guard var components = URLComponents(string: "https://router.project-osrm.org/route/v1/driving/\(coordinatePath)") else {
            print("[RoutingManager] Failed to build request URL for \(origin) -> \(destination)")
            errorMessage = "Couldn't build a routing request for that destination."
            return
        }
        components.queryItems = [
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
        ]
        guard let url = components.url else {
            print("[RoutingManager] Failed to resolve request URL")
            errorMessage = "Couldn't build a routing request for that destination."
            return
        }

        print("[RoutingManager] GET \(url)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                print("[RoutingManager] No HTTP response")
                errorMessage = "The routing service couldn't be reached."
                return
            }
            print("[RoutingManager] Response status: \(http.statusCode)")
            guard 200..<300 ~= http.statusCode else {
                errorMessage = "The routing service couldn't be reached."
                return
            }
            let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
            guard decoded.code == "Ok", let osrmRoute = decoded.routes.first else {
                let message = decoded.message ?? "No route found between those points."
                print("[RoutingManager] OSRM returned no route: \(message)")
                errorMessage = message
                return
            }
            let parsed = Self.parse(osrmRoute)
            steps = parsed.steps
            routePolyline = parsed.polyline
            totalDistance = parsed.totalDistance
            totalDuration = parsed.totalDuration
            currentStepIndex = 0
            print("[RoutingManager] Route parsed: \(parsed.steps.count) steps, \(Int(parsed.totalDistance))m, \(parsed.polyline.count) polyline points")
        } catch {
            print("[RoutingManager] Request failed: \(error.localizedDescription)")
            errorMessage = "Couldn't fetch a route: \(error.localizedDescription)"
        }
    }

    func clear() {
        steps = []
        routePolyline = []
        totalDistance = 0
        totalDuration = 0
        currentStepIndex = 0
        errorMessage = nil
    }

    /// Advances to the next step once the traveller gets within `arrivalRadius` of the
    /// current step's endpoint.
    func updateStepIfNeeded(userLocation: CLLocationCoordinate2D) {
        guard let step = currentStep, !isFinished else { return }
        if CompassManager.distance(from: userLocation, to: step.endCoordinate) <= arrivalRadius {
            currentStepIndex += 1
            print("[RoutingManager] Arrived at step endpoint, advancing to step \(currentStepIndex)")
        }
    }

    private static func parse(_ osrmRoute: OSRMRoute) -> (steps: [RouteStep], polyline: [CLLocationCoordinate2D], totalDistance: Double, totalDuration: TimeInterval) {
        var steps: [RouteStep] = []
        for leg in osrmRoute.legs {
            for step in leg.steps {
                let coordinates = step.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                let start = coordinates.first ?? CLLocationCoordinate2D(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0])
                let end = coordinates.last ?? start
                let bearing = CompassManager.bearing(from: start, to: end)
                steps.append(RouteStep(
                    instruction: humanize(maneuver: step.maneuver, roadName: step.name),
                    distance: step.distance,
                    duration: step.duration,
                    name: step.name,
                    maneuverType: step.maneuver.type,
                    maneuverModifier: step.maneuver.modifier,
                    startCoordinate: start,
                    endCoordinate: end,
                    bearing: bearing
                ))
            }
        }
        let polyline = osrmRoute.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        return (steps, polyline, osrmRoute.distance, osrmRoute.duration)
    }

    /// Turns OSRM's terse maneuver codes into the kind of short phrase the turn card shows.
    private static func humanize(maneuver: OSRMManeuver, roadName: String) -> String {
        let road = roadName.isEmpty ? "the road ahead" : roadName
        switch maneuver.type {
        case "depart": return "Head out"
        case "arrive": return "You've arrived"
        case "turn", "end of road":
            let dir = maneuver.modifier ?? "onto"
            return "Turn \(dir) onto \(road)"
        case "new name": return "Continue onto \(road)"
        case "merge": return "Merge onto \(road)"
        case "roundabout", "rotary": return "Enter the roundabout"
        case "fork":
            let dir = maneuver.modifier ?? "ahead"
            return "Keep \(dir) at the fork"
        case "on ramp": return "Take the ramp onto \(road)"
        case "off ramp": return "Take the exit onto \(road)"
        default:
            if let modifier = maneuver.modifier {
                return "Bear \(modifier) onto \(road)"
            }
            return "Continue onto \(road)"
        }
    }
}

// MARK: - OSRM response models

private struct OSRMResponse: Decodable {
    let code: String
    let message: String?
    let routes: [OSRMRoute]
}

private struct OSRMRoute: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let geometry: OSRMGeometry
    let legs: [OSRMLeg]
}

private struct OSRMLeg: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let steps: [OSRMStep]
}

private struct OSRMStep: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let name: String
    let maneuver: OSRMManeuver
    let geometry: OSRMGeometry
}

private struct OSRMManeuver: Decodable {
    /// [longitude, latitude], per OSRM's convention.
    let location: [Double]
    let type: String
    let modifier: String?
}

/// A GeoJSON LineString's `coordinates` — each element is `[longitude, latitude]`.
private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}
