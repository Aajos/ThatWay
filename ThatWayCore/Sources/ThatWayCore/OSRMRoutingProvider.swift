//
//  OSRMRoutingProvider.swift
//  ThatWayCore
//
//  The only file in the app that knows OSRM's JSON shape. Translates it into the app's own
//  `Route`/`RouteStep` model (RouteModels.swift) and `RoutingError` cases — everything else,
//  including `RoutingManager`, never sees an OSRM type.
//

import CoreLocation
import Foundation

public final class OSRMRoutingProvider: RoutingProvider {
    private let session: URLSession
    private let baseURL: (TravelProfile) -> String

    /// `baseURL` says which OSRM host serves each profile, `userAgent` identifies the app (the public servers ask for it).
    /// `session` is injectable so tests can swap in a `URLProtocol`-mocked one — production code gets an ephemeral
    /// session (no on-disk cache of where anyone has routed) with a 5 second timeout.
    public init(baseURL: @escaping (TravelProfile) -> String, userAgent: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
            self.session = URLSession(configuration: configuration)
        }
    }

    public func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async throws -> Route {
        let coordinatePath = "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
        guard var components = URLComponents(string: "\(baseURL(profile))/\(coordinatePath)") else {
            throw RoutingError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "annotations", value: "distance,duration,speed"),
        ]
        guard let url = components.url else { throw RoutingError.invalidResponse }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .timedOut {
            throw RoutingError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw RoutingError.network
        }

        guard let http = response as? HTTPURLResponse else { throw RoutingError.invalidResponse }
        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw RoutingError.rateLimited(retryAfter: retryAfter)
        }
        if (500...599).contains(http.statusCode) {
            throw RoutingError.serverError(http.statusCode)
        }
        guard 200..<300 ~= http.statusCode else { throw RoutingError.invalidResponse }

        let decoded: OSRMResponse
        do {
            decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        } catch {
            throw RoutingError.invalidResponse
        }

        switch decoded.code {
        case "Ok": break
        case "NoSegment": throw RoutingError.noRoadNearby
        case "NoRoute": throw RoutingError.noRoute
        default: throw RoutingError.noRoute
        }
        guard let osrmRoute = decoded.routes?.first else { throw RoutingError.noRoute }

        return Self.makeRoute(from: osrmRoute)
    }

    // MARK: - OSRM JSON -> Route

    private static func makeRoute(from osrmRoute: OSRMRoute) -> Route {
        let geometry = osrmRoute.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(geometry.count)
        for index in geometry.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + CompassManager.distance(from: geometry[index - 1], to: geometry[index]))
        }

        struct Raw {
            let step: OSRMStep
            let start: CLLocationCoordinate2D
            let end: CLLocationCoordinate2D
            let bearing: CLLocationDirection
        }
        var raws: [Raw] = []
        for leg in osrmRoute.legs {
            for step in leg.steps {
                let coordinates = step.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                let start = coordinates.first ?? CLLocationCoordinate2D(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0])
                let end = coordinates.last ?? start
                raws.append(Raw(step: step, start: start, end: end, bearing: CompassManager.bearing(from: start, to: end)))
            }
        }

        // Where each step's manoeuvre sits along the route: its start coordinate is one of the
        // geometry's own vertices, so find it scanning forward (never backward) and read the
        // running index/distance there.
        var startAlongs: [Double] = []
        var startIndices: [Int] = []
        var vertex = 0
        for raw in raws {
            var best = vertex
            var bestDistance = Double.greatestFiniteMagnitude
            var index = vertex
            while index < geometry.count {
                let d = CompassManager.distance(from: geometry[index], to: raw.start)
                if d < bestDistance { bestDistance = d; best = index }
                if d < 0.5 { break }
                index += 1
            }
            vertex = best
            startAlongs.append(cumulative[best])
            startIndices.append(best)
        }
        let routeEnd = cumulative.last ?? 0
        let lastIndex = geometry.count - 1

        var steps: [RouteStep] = []
        for (index, raw) in raws.enumerated() {
            let step = raw.step
            let intersections: [RouteIntersection] = step.intersections.map { intersection in
                var excluded = Set<Int>()
                if let inIndex = intersection.in { excluded.insert(inIndex) }
                if let outIndex = intersection.out { excluded.insert(outIndex) }
                let otherBearings: [RouteBearing] = intersection.bearings.enumerated()
                    .filter { offset, _ in !excluded.contains(offset) }
                    .map { offset, bearing in
                        let entryFlag = intersection.entry.indices.contains(offset) ? intersection.entry[offset] : true
                        return RouteBearing(bearing: CLLocationDirection(bearing), entry: entryFlag)
                    }
                let outBearing = intersection.out.flatMap { intersection.bearings.indices.contains($0) ? CLLocationDirection(intersection.bearings[$0]) : nil }
                return RouteIntersection(
                    coordinate: CLLocationCoordinate2D(latitude: intersection.location[1], longitude: intersection.location[0]),
                    otherBearings: otherBearings,
                    outBearing: outBearing
                )
            }
            let approachBearing = index > 0 ? raws[index - 1].bearing : raw.bearing
            let exitBearing = index + 1 < raws.count ? raws[index + 1].bearing : raw.bearing
            let shape = turnShape(type: step.maneuver.type, modifier: step.maneuver.modifier, approach: approachBearing, exit: exitBearing)
            let endIndex = index + 1 < startIndices.count ? startIndices[index + 1] : lastIndex
            steps.append(RouteStep(
                id: UUID(),
                instruction: humanize(maneuver: step.maneuver, roadName: step.name),
                distance: step.distance,
                duration: step.duration,
                name: step.name,
                maneuverType: step.maneuver.type,
                maneuverModifier: step.maneuver.modifier,
                startCoordinate: raw.start,
                endCoordinate: raw.end,
                bearing: raw.bearing,
                intersections: intersections,
                startAlong: step.maneuver.type == "arrive" ? routeEnd : startAlongs[index],
                endAlong: index + 1 < startAlongs.count ? startAlongs[index + 1] : routeEnd,
                startIndex: startIndices[index],
                endIndex: endIndex,
                turn: shape,
                exitNumber: step.maneuver.exit,
                exitBearing: step.maneuver.bearingAfter.map(CLLocationDirection.init)
            ))
        }

        var rawDurations: [Double] = []
        var segmentSpeeds: [Double] = []
        for leg in osrmRoute.legs {
            rawDurations += leg.annotation?.duration ?? []
            segmentSpeeds += leg.annotation?.speed ?? []
        }
        var segmentDurations: [Double] = []
        let expectedSegments = geometry.count - 1
        if rawDurations.count == expectedSegments, rawDurations.reduce(0, +) > 0 {
            let scale = osrmRoute.duration / rawDurations.reduce(0, +)
            segmentDurations = rawDurations.map { $0 * scale }
        } else {
            segmentSpeeds = []
        }

        return Route(
            geometry: geometry, distance: osrmRoute.distance, duration: osrmRoute.duration, steps: steps,
            segmentDurations: segmentDurations, segmentSpeeds: segmentSpeeds
        )
    }

    /// The signed angle (-180...180, positive = clockwise/right) from one bearing to another.
    private static func signedAngle(from: CLLocationDirection, to: CLLocationDirection) -> Double {
        var diff = (to - from).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    private static func shape(forAngle angle: Double) -> TurnShape {
        let magnitude = abs(angle)
        let side: TurnSide = magnitude < 20 ? .straight : (angle < 0 ? .left : .right)
        let severity: TurnSeverity
        switch magnitude {
        case ..<60: severity = .slight
        case ..<135: severity = .normal
        case ..<165: severity = .sharp
        default: severity = .uTurn
        }
        return TurnShape(side: side, severity: side == .straight ? .normal : severity)
    }

    /// Left/right/straight and how hard, for a manoeuvre. Roundabouts are judged by their
    /// *exit* — the angle between the way you approach and the way the exit road leaves — so a
    /// straight-through exit reads as straight however sharply the circle itself curves.
    private static func turnShape(type: String, modifier: String?, approach: CLLocationDirection, exit: CLLocationDirection) -> TurnShape {
        if type == "roundabout" || type == "rotary" {
            return shape(forAngle: signedAngle(from: approach, to: exit))
        }
        guard let modifier else { return .straight }
        switch modifier {
        case "uturn": return TurnShape(side: .left, severity: .uTurn)
        case "sharp left": return TurnShape(side: .left, severity: .sharp)
        case "left": return TurnShape(side: .left, severity: .normal)
        case "slight left": return TurnShape(side: .left, severity: .slight)
        case "sharp right": return TurnShape(side: .right, severity: .sharp)
        case "right": return TurnShape(side: .right, severity: .normal)
        case "slight right": return TurnShape(side: .right, severity: .slight)
        default: return .straight
        }
    }

    /// Turns OSRM's terse maneuver codes into the kind of short phrase the turn card shows.
    private static func humanize(maneuver: OSRMManeuver, roadName: String) -> String {
        let road = roadName.isEmpty ? "the road ahead" : roadName
        switch maneuver.type {
        case "depart": return "Head out"
        case "arrive": return "You've arrived"
        case "turn", "end of road":
            let dir = maneuver.modifier ?? ""
            if roadName.isEmpty { return dir.isEmpty ? "Turn" : "Turn \(dir)" }
            return dir.isEmpty ? "Turn onto \(road)" : "Turn \(dir) onto \(road)"
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

struct OSRMResponse: Decodable {
    let code: String
    let message: String?
    /// Absent entirely on an error response (`NoRoute`/`NoSegment`/etc.) — only ever populated
    /// when `code == "Ok"`.
    let routes: [OSRMRoute]?
}

struct OSRMRoute: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let geometry: OSRMGeometry
    let legs: [OSRMLeg]
}

struct OSRMLeg: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let steps: [OSRMStep]
    let annotation: OSRMAnnotation?
}

/// Per-segment road data OSRM attaches when asked (`annotations=`): each array has one entry per
/// consecutive pair of polyline vertices.
struct OSRMAnnotation: Decodable {
    let duration: [Double]?
    let speed: [Double]?
}

struct OSRMStep: Decodable {
    let distance: CLLocationDistance
    let duration: TimeInterval
    let name: String
    let maneuver: OSRMManeuver
    let geometry: OSRMGeometry
    let intersections: [OSRMIntersection]
}

/// One real intersection along a step's road, as OSRM reports it — every road meeting
/// there (`bearings`), which of those the route arrived on (`in`) and continues along
/// (`out`), by index into `bearings`/`entry`. `entry` (whether each bearing can legally be
/// entered — `true` for a real option, `false` for a one-way street the wrong way or a
/// restricted turn) is carried through unfiltered into `RouteIntersection.otherBearings`;
/// `GuidanceLineView` applies and logs the actual entry/bearing/name filter stages itself.
struct OSRMIntersection: Decodable {
    /// [longitude, latitude], per OSRM's convention.
    let location: [Double]
    let bearings: [Int]
    let entry: [Bool]
    let `in`: Int?
    let out: Int?
}

struct OSRMManeuver: Decodable {
    /// [longitude, latitude], per OSRM's convention.
    let location: [Double]
    let type: String
    let modifier: String?
    /// For roundabouts: which exit to take, counting from the entry.
    let exit: Int?
    let bearingAfter: Int?

    private enum CodingKeys: String, CodingKey {
        case location, type, modifier, exit
        case bearingAfter = "bearing_after"
    }
}

/// A GeoJSON LineString's `coordinates` — each element is `[longitude, latitude]`.
struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}
