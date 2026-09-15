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

/// One turn-by-turn instruction, with the coordinate at which it's actioned.
struct RouteStep: Identifiable {
    let id = UUID()
    let instruction: String
    let distance: CLLocationDistance
    let duration: TimeInterval
    let maneuverType: String
    let maneuverModifier: String?
    let coordinate: CLLocationCoordinate2D

    /// A rough left/right/straight bucket for the turn-arrow glyph, derived from OSRM's
    /// maneuver modifier (e.g. "slight left", "sharp right", "straight").
    var turnDirection: TurnDir {
        guard let modifier = maneuverModifier else { return .straight }
        if modifier.contains("left") { return .left }
        if modifier.contains("right") { return .right }
        return .straight
    }
}

/// A decoded route: turn-by-turn steps, the full path geometry, and per-leg distances.
struct RouteResult {
    let steps: [RouteStep]
    let polyline: [CLLocationCoordinate2D]
    let totalDistance: CLLocationDistance
    let totalDuration: TimeInterval
    let legDistances: [CLLocationDistance]
}

@MainActor
final class RoutingManager: ObservableObject {
    @Published private(set) var route: RouteResult?
    @Published private(set) var steps: [RouteStep] = []
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// How close (metres) the traveller needs to get to a step's maneuver point before
    /// guidance advances to the next instruction.
    private let arrivalRadius: CLLocationDistance = 50

    var currentStep: RouteStep? { steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil }
    var nextStep: RouteStep? { steps.indices.contains(currentStepIndex + 1) ? steps[currentStepIndex + 1] : nil }
    var isFinished: Bool { !steps.isEmpty && currentStepIndex >= steps.count - 1 }
    var hasRoute: Bool { !steps.isEmpty }

    func fetchRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: String = "driving"
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // OSRM takes coordinates as "lon,lat" — the opposite order from CLLocationCoordinate2D.
        let coordinatePath = "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
        guard var components = URLComponents(string: "https://router.project-osrm.org/route/v1/\(profile)/\(coordinatePath)") else {
            errorMessage = "Couldn't build a routing request for that destination."
            return
        }
        components.queryItems = [
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "geometries", value: "polyline"),
            URLQueryItem(name: "overview", value: "full"),
        ]
        guard let url = components.url else {
            errorMessage = "Couldn't build a routing request for that destination."
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                errorMessage = "The routing service couldn't be reached."
                return
            }
            let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
            guard decoded.code == "Ok", let osrmRoute = decoded.routes.first else {
                errorMessage = decoded.message ?? "No route found between those points."
                return
            }
            let parsed = Self.parse(osrmRoute)
            route = parsed
            steps = parsed.steps
            currentStepIndex = 0
        } catch {
            errorMessage = "Couldn't fetch a route: \(error.localizedDescription)"
        }
    }

    func clear() {
        route = nil
        steps = []
        currentStepIndex = 0
        errorMessage = nil
    }

    /// Advances to the next step once the traveller gets within `arrivalRadius` of the
    /// current step's maneuver point.
    func updateProgress(userLocation: CLLocationCoordinate2D) {
        guard let step = currentStep, !isFinished else { return }
        let stepLocation = CLLocation(latitude: step.coordinate.latitude, longitude: step.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        if userLoc.distance(from: stepLocation) <= arrivalRadius {
            currentStepIndex += 1
        }
    }

    private static func parse(_ osrmRoute: OSRMRoute) -> RouteResult {
        var steps: [RouteStep] = []
        var legDistances: [CLLocationDistance] = []
        for leg in osrmRoute.legs {
            legDistances.append(leg.distance)
            for step in leg.steps {
                let coordinate = CLLocationCoordinate2D(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0])
                steps.append(RouteStep(
                    instruction: humanize(maneuver: step.maneuver, roadName: step.name),
                    distance: step.distance,
                    duration: step.duration,
                    maneuverType: step.maneuver.type,
                    maneuverModifier: step.maneuver.modifier,
                    coordinate: coordinate
                ))
            }
        }
        return RouteResult(
            steps: steps,
            polyline: PolylineCodec.decode(osrmRoute.geometry),
            totalDistance: osrmRoute.distance,
            totalDuration: osrmRoute.duration,
            legDistances: legDistances
        )
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
    let geometry: String
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
}

private struct OSRMManeuver: Decodable {
    /// [longitude, latitude], per OSRM's convention.
    let location: [Double]
    let type: String
    let modifier: String?
}

// MARK: - Polyline geometry decoding

/// Decodes the Google/OSRM encoded-polyline format (precision 5) into coordinates.
enum PolylineCodec {
    static func decode(_ encoded: String, precision: Double = 1e5) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            var shift = 0
            var result = 0
            var byte: Int
            repeat {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20
            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            shift = 0
            result = 0
            repeat {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20
            lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return coordinates
    }
}
