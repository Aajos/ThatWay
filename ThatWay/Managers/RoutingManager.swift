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

/// One real intersection the route passes through along a step's road segment — whether
/// the route actually turns there or just continues straight through. `otherBearings`
/// holds every *other* road meeting at this point (true-north degrees), with the road the
/// route arrived on and the one it continues along already excluded — these are the roads
/// not taken, for `GuidanceLineView`'s side-branch markers. Each carries OSRM's own raw
/// `entry` flag (whether that road can legally be turned onto at all) unfiltered — the
/// entry/bearing/name filter stages themselves live in `GuidanceLineView` now, so its debug
/// log can show exactly how many candidates survive each stage rather than only ever seeing
/// an already-filtered list. `outBearing` (the road actually taken) is kept separately so a
/// caller can filter out "other" roads that are really just the same road's own curve
/// re-entering the graph (a roundabout's arc, a divided road's other carriageway) rather
/// than a genuinely different one.
struct RouteIntersection {
    let coordinate: CLLocationCoordinate2D
    let otherBearings: [(bearing: CLLocationDirection, entry: Bool)]
    let outBearing: CLLocationDirection?
}

enum TurnSide { case left, right, straight }
enum TurnSeverity { case slight, normal, sharp, uTurn }

/// What a manoeuvre actually looks like to the traveller: which way, and how hard. For a
/// roundabout this describes the *exit* relative to the way you approach it (left, straight,
/// right) — never the entry, which is always "turn into the circle".
struct TurnShape {
    var side: TurnSide
    var severity: TurnSeverity
    static let straight = TurnShape(side: .straight, severity: .normal)

    var dir: TurnDir {
        switch side {
        case .left: return .left
        case .right: return .right
        case .straight: return .straight
        }
    }
}

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
    /// Where this step's own road segment begins and ends.
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    /// The heading to point the compass along for this step, computed from
    /// `startCoordinate` to `endCoordinate` via `CompassManager.bearing`.
    let bearing: CLLocationDirection
    /// Every real intersection along this step's own road — not just its final manoeuvre
    /// point — straight from OSRM's own per-step intersection list.
    let intersections: [RouteIntersection]
    /// Metres along the whole route where this step's manoeuvre happens / where the next
    /// begins — how progress is measured, instead of a proximity radius that a fast
    /// traveller can step right over between two location checks.
    let startAlong: Double
    let endAlong: Double
    let turn: TurnShape
    let exitNumber: Int?

    var turnDirection: TurnDir { turn.dir }
}

enum ManeuverKind { case depart, turn, roundabout, fork, merge, ramp, keepGoing, arrive }

/// One guidance card — one instruction for the whole trip, built up front the moment a route
/// arrives so the full list can be read (and scrolled) before setting off. A roundabout is a
/// single card covering entry *and* exit; "exit roundabout" steps never get their own.
struct GuidanceCard: Identifiable {
    /// The index of the route step this card's manoeuvre belongs to.
    let id: Int
    let kind: ManeuverKind
    let title: String
    /// The condensed two-line form the on-screen cards use: a short action ("Turn left", "2nd exit")
    /// and the road it leads onto, abbreviated ("Lakewood Dr") — never a full spoken sentence.
    let shortTitle: String
    let shortRoad: String
    let roadName: String
    let turn: TurnShape
    let exitNumber: Int?
    let coordinate: CLLocationCoordinate2D
    /// Where the compass aims for this card: the manoeuvre point itself, except a roundabout,
    /// where it's the *exit* — so the needle shows where the exit stands (left, straight or
    /// right), never a hard turn into the circle.
    let exitCoordinate: CLLocationCoordinate2D
    /// Metres along the route where the manoeuvre starts, and where it's finished (the same
    /// point, except a roundabout, which finishes at its exit).
    let startAlong: Double
    let completeAlong: Double
    /// Metres from finishing this manoeuvre to the next card's manoeuvre.
    var legLength: Double

    var isRoundabout: Bool { kind == .roundabout }
}

@MainActor
final class RoutingManager: ObservableObject {
    @Published private(set) var steps: [RouteStep] = []
    @Published private(set) var routePolyline: [CLLocationCoordinate2D] = []
    /// The step the traveller is currently *on* — the one whose manoeuvre they've already made.
    @Published var currentStepIndex = 0
    @Published private(set) var totalDistance: Double = 0
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Every instruction for the whole trip, built once when the route arrives.
    @Published private(set) var cards: [GuidanceCard] = []
    /// How far (metres) along the route the traveller has got. Everything on the way card —
    /// which instruction is current and how far off it is — comes from this, so it's measured
    /// along the actual road rather than as a straight line, and can't be skipped by a fast
    /// traveller stepping over a proximity circle between two location checks.
    @Published private(set) var progressAlong: Double = 0
    private(set) var routeLength: Double = 0
    /// OSRM's per-segment road data along the polyline (one entry per vertex pair, all legs joined):
    /// how long each segment takes and how fast the road is (its profile speed, m/s — from road class
    /// and speed limits, not live traffic). `segmentDurations` is scaled to sum to the route's own
    /// total duration, so junction/turn penalties OSRM adds on top of raw travel time are included.
    private(set) var segmentDurations: [Double] = []
    private(set) var segmentSpeeds: [Double] = []
    var currentSegment: Int { lastSegmentIndex }
    private var cumulative: [Double] = []
    private var lastSegmentIndex = 0

    /// `routePolyline` trimmed back to start at the traveller's current position — so the
    /// line on screen shows only the road still ahead, not the ground already covered.
    @Published private(set) var remainingPolyline: [CLLocationCoordinate2D] = []
    /// True once the traveller has drifted further from the route than `offRouteThreshold`
    /// allows — a wrong turn or a real GPS position that's left the planned road — signaling
    /// that whoever's driving this route forward should fetch a fresh one.
    @Published private(set) var isOffRoute = false

    /// How far (metres) the traveller can be from the route's OSRM-snapped start point and
    /// still count as "at the start". OSRM snaps the route onto the nearest road it knows
    /// about, which can sit well outside the walking/driving corridor tolerance from a raw
    /// coordinate (an address, a mock GPS fix) — without this, that snap gap alone reads as
    /// having already drifted off a route nobody has taken a step on yet.
    private let startSnapRadius: CLLocationDistance = 50

    var currentStep: RouteStep? { steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil }
    var nextStep: RouteStep? { steps.indices.contains(currentStepIndex + 1) ? steps[currentStepIndex + 1] : nil }
    var isFinished: Bool { !steps.isEmpty && currentStepIndex >= steps.count - 1 }
    var hasRoute: Bool { !steps.isEmpty }

    var remainingDistance: Double { max(0, routeLength - progressAlong) }

    // MARK: Card progress

    /// The instruction the traveller is heading for right now: the first card whose manoeuvre
    /// isn't finished yet. A roundabout stays current all the way round to its exit.
    var currentCardIndex: Int? {
        cards.firstIndex { $0.completeAlong > progressAlong + 1 }
    }
    var upcomingCard: GuidanceCard? { currentCardIndex.map { cards[$0] } }

    /// Metres from the traveller to the current instruction's action point — along the road.
    /// (A roundabout counts down to its entry first, then to its exit once inside.)
    var distanceToUpcoming: Double {
        guard let card = upcomingCard else { return 0 }
        return distanceTo(card)
    }

    func distanceTo(_ card: GuidanceCard) -> Double {
        if card.isRoundabout, progressAlong >= card.startAlong {
            return max(0, card.completeAlong - progressAlong)
        }
        return max(0, card.startAlong - progressAlong)
    }

    /// How far through the current leg (previous manoeuvre → this one) the traveller still has
    /// to go, 0...1 — 1 straight after the last turn, 0 at the next one.
    var legFraction: Double {
        guard let index = currentCardIndex else { return 0 }
        let legStart = index > 0 ? cards[index - 1].completeAlong : 0
        let legLength = max(1, cards[index].startAlong - legStart)
        return max(0, min(1, (cards[index].startAlong - progressAlong) / legLength))
    }

    // MARK: Fetching

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
            URLQueryItem(name: "annotations", value: "distance,duration,speed"),
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
            print("[RoutingManager] Route distance: \(osrmRoute.distance) m, polyline points: \(osrmRoute.geometry.coordinates.count)")
            let parsed = Self.parse(osrmRoute, destination: destination)
            steps = parsed.steps
            cards = parsed.cards
            routePolyline = parsed.polyline
            cumulative = parsed.cumulative
            segmentDurations = parsed.segmentDurations
            segmentSpeeds = parsed.segmentSpeeds
            routeLength = parsed.cumulative.last ?? 0
            remainingPolyline = parsed.polyline
            isOffRoute = false
            totalDistance = parsed.totalDistance
            totalDuration = parsed.totalDuration
            currentStepIndex = 0
            progressAlong = 0
            lastSegmentIndex = 0
            print("[RoutingManager] Route parsed: \(parsed.steps.count) steps, \(parsed.cards.count) cards, \(Int(parsed.totalDistance))m")
        } catch {
            print("[RoutingManager] Request failed: \(error.localizedDescription)")
            errorMessage = "Couldn't fetch a route: \(error.localizedDescription)"
        }
    }

    func clear() {
        steps = []
        cards = []
        routePolyline = []
        cumulative = []
        segmentDurations = []
        segmentSpeeds = []
        remainingPolyline = []
        isOffRoute = false
        totalDistance = 0
        totalDuration = 0
        routeLength = 0
        currentStepIndex = 0
        progressAlong = 0
        lastSegmentIndex = 0
        errorMessage = nil
    }

    // MARK: Progress

    private struct Located {
        let point: CLLocationCoordinate2D
        let distance: CLLocationDistance
        let along: Double
        let segment: Int
    }

    /// Finds the traveller on the route: nearest point on the polyline, searched in a window
    /// around where they last were (so a road that loops back near itself can't yank progress
    /// to the wrong stretch), falling back to the whole line if nothing in the window is close.
    private func locate(_ location: CLLocationCoordinate2D) -> Located? {
        guard routePolyline.count > 1, cumulative.count == routePolyline.count else { return nil }
        let lastSegment = routePolyline.count - 2
        let low = max(0, min(lastSegment, lastSegmentIndex - 3))
        let high = min(lastSegment, lastSegmentIndex + 120)
        var best: Located?
        if let windowed = CompassManager.nearestPoint(on: Array(routePolyline[low...(high + 1)]), to: location) {
            let segment = low + windowed.segmentIndex
            best = Located(point: windowed.point, distance: windowed.distance, along: alongDistance(segment: segment, point: windowed.point), segment: segment)
        }
        if best == nil || best!.distance > 60, let global = CompassManager.nearestPoint(on: routePolyline, to: location),
           best == nil || global.distance < best!.distance {
            best = Located(point: global.point, distance: global.distance, along: alongDistance(segment: global.segmentIndex, point: global.point), segment: global.segmentIndex)
        }
        return best
    }

    private func alongDistance(segment: Int, point: CLLocationCoordinate2D) -> Double {
        cumulative[segment] + CompassManager.distance(from: routePolyline[segment], to: point)
    }

    /// The cheap half of progress tracking — where along the route, and so which instruction —
    /// safe to run every second or so. Off-route detection stays in `updateProgress`.
    func advanceProgress(userLocation: CLLocationCoordinate2D) {
        guard let located = locate(userLocation), located.distance < 150 else { return }
        lastSegmentIndex = located.segment
        if located.along > progressAlong { progressAlong = located.along }
        if let index = steps.lastIndex(where: { $0.startAlong <= progressAlong }), index > currentStepIndex {
            currentStepIndex = index
        }
    }

    /// Called on each `LocationCheckScheduler` poll with the traveller's real (or simulated)
    /// position and current activity: brings progress up to date, trims `remainingPolyline`
    /// down to the road still ahead of them, and flags `isOffRoute` when they've drifted further
    /// than the activity's real corridor tolerance (15m walking, 30m driving) from the planned
    /// line — for whoever owns navigation (AppModel) to fetch a fresh route.
    func updateProgress(userLocation: CLLocationCoordinate2D, activity: GuidanceActivity) {
        guard !routePolyline.isEmpty else {
            remainingPolyline = []
            isOffRoute = false
            return
        }
        advanceProgress(userLocation: userLocation)
        let threshold = activity.corridorRadius
        guard let routeStartPoint = routePolyline.first else { return }
        let distanceToStart = CompassManager.distance(from: userLocation, to: routeStartPoint)
        if distanceToStart <= startSnapRadius, progressAlong < 60 {
            isOffRoute = false
            remainingPolyline = routePolyline
        } else if let located = locate(userLocation) {
            isOffRoute = located.distance > threshold
            remainingPolyline = [located.point] + routePolyline.suffix(from: min(located.segment + 1, routePolyline.count))
        }
    }

    // MARK: Parsing

    private struct Parsed {
        let steps: [RouteStep]
        let cards: [GuidanceCard]
        let polyline: [CLLocationCoordinate2D]
        let cumulative: [Double]
        let segmentDurations: [Double]
        let segmentSpeeds: [Double]
        let totalDistance: Double
        let totalDuration: TimeInterval
    }

    private static func parse(_ osrmRoute: OSRMRoute, destination: CLLocationCoordinate2D) -> Parsed {
        var polyline = osrmRoute.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        // OSRM ends the route on the nearest road, which can be well short of the place itself (a
        // reserve, a car park, a shop set back from the street). The last stretch is joined on here
        // so the route — and the flag, the distance and the card — end at the destination itself.
        let roadEnd = polyline.last
        let finalGap = roadEnd.map { CompassManager.distance(from: $0, to: destination) } ?? 0
        let extendsToDestination = finalGap > 4
        if extendsToDestination { polyline.append(destination) }
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(polyline.count)
        for index in polyline.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + CompassManager.distance(from: polyline[index - 1], to: polyline[index]))
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
        // polyline's own vertices, so find it scanning forward (never backward) and read the
        // running distance there.
        var startAlongs: [Double] = []
        var vertex = 0
        for raw in raws {
            var best = vertex
            var bestDistance = Double.greatestFiniteMagnitude
            var index = vertex
            while index < polyline.count {
                let d = CompassManager.distance(from: polyline[index], to: raw.start)
                if d < bestDistance { bestDistance = d; best = index }
                if d < 0.5 { break }
                index += 1
            }
            vertex = best
            startAlongs.append(cumulative[best])
        }
        let routeEnd = cumulative.last ?? 0

        var steps: [RouteStep] = []
        for (index, raw) in raws.enumerated() {
            let step = raw.step
            let intersections: [RouteIntersection] = step.intersections.map { intersection in
                var excluded = Set<Int>()
                if let inIndex = intersection.in { excluded.insert(inIndex) }
                if let outIndex = intersection.out { excluded.insert(outIndex) }
                // Only the road arrived on and the one continued along are dropped here
                // — everything else (including `entry: false` roads you can't legally
                // turn onto) is kept raw, with its own entry flag, so GuidanceLineView's
                // filter stages can be logged individually instead of collapsing straight
                // to a final list.
                let otherBearings: [(bearing: CLLocationDirection, entry: Bool)] = intersection.bearings.enumerated()
                    .filter { offset, _ in !excluded.contains(offset) }
                    .map { offset, bearing in
                        let entryFlag = intersection.entry.indices.contains(offset) ? intersection.entry[offset] : true
                        return (CLLocationDirection(bearing), entryFlag)
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
            steps.append(RouteStep(
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
                // "Arrive" happens at the very end of the (extended) route, not at the road's end.
                startAlong: step.maneuver.type == "arrive" ? routeEnd : startAlongs[index],
                endAlong: index + 1 < startAlongs.count ? startAlongs[index + 1] : routeEnd,
                turn: shape,
                exitNumber: step.maneuver.exit
            ))
        }
        var rawDurations: [Double] = []
        var segmentSpeeds: [Double] = []
        for leg in osrmRoute.legs {
            rawDurations += leg.annotation?.duration ?? []
            segmentSpeeds += leg.annotation?.speed ?? []
        }
        // Only trusted when it lines up with the polyline exactly; otherwise ETA falls back to
        // distance ÷ a typical speed.
        var segmentDurations: [Double] = []
        let osrmSegments = polyline.count - 1 - (extendsToDestination ? 1 : 0)
        if rawDurations.count == osrmSegments, let rawTotal = Optional(rawDurations.reduce(0, +)), rawTotal > 0 {
            let scale = osrmRoute.duration / rawTotal
            segmentDurations = rawDurations.map { $0 * scale }
            if extendsToDestination {
                // The last stretch is on foot from the road end.
                segmentDurations.append(finalGap / 1.4)
                segmentSpeeds.append(1.4)
            }
        } else {
            segmentSpeeds = []
        }
        return Parsed(
            steps: steps,
            cards: buildCards(from: steps, bearingsAfter: raws.map { $0.step.maneuver.bearingAfter }),
            polyline: polyline,
            cumulative: cumulative,
            segmentDurations: segmentDurations,
            segmentSpeeds: segmentSpeeds,
            totalDistance: osrmRoute.distance,
            totalDuration: osrmRoute.duration
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

    private static func cardinal(_ bearing: CLLocationDirection) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int(((bearing.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8]
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// One card per real instruction, for the whole route. "Exit roundabout" steps are folded
    /// into their roundabout's card.
    /// "Lakewood Drive" → "Lakewood Dr", "Burwood Highway" → "Burwood Hwy": the common road-type words
    /// abbreviated, so road names fit a card line.
    static func shortRoadName(_ name: String) -> String {
        let table = ["Road": "Rd", "Street": "St", "Drive": "Dr", "Highway": "Hwy", "Avenue": "Ave", "Boulevard": "Blvd",
                     "Court": "Ct", "Crescent": "Cres", "Lane": "Ln", "Place": "Pl", "Parade": "Pde", "Terrace": "Tce",
                     "Freeway": "Fwy", "Circuit": "Cct", "Esplanade": "Esp", "Grove": "Gr", "Close": "Cl"]
        return name.split(separator: " ").map { table[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func buildCards(from steps: [RouteStep], bearingsAfter: [Int?]) -> [GuidanceCard] {
        var cards: [GuidanceCard] = []
        for (index, step) in steps.enumerated() {
            if step.maneuverType == "exit roundabout" || step.maneuverType == "exit rotary" { continue }
            let road = step.name
            let onto = road.isEmpty ? "" : " onto \(road)"
            let kind: ManeuverKind
            let title: String
            var shortTitle: String
            var shortRoad = shortRoadName(road)
            let complete: Double
            var exitCoordinate = step.intersections.first?.coordinate ?? step.startCoordinate
            let sideWord = step.turn.side == .left ? "left" : step.turn.side == .right ? "right" : "straight"
            switch step.maneuverType {
            case "depart":
                kind = .depart
                let heading = bearingsAfter[index].map { "Head \(cardinal(Double($0)))" } ?? "Head out"
                title = road.isEmpty ? heading : "\(heading) on \(road)"
                shortTitle = heading
                complete = step.startAlong
            case "arrive":
                kind = .arrive
                title = "Arrive at your destination"
                shortTitle = "Arrive"
                shortRoad = ""
                complete = step.startAlong
            case "roundabout", "rotary":
                kind = .roundabout
                let exit = step.exitNumber.map { "take the \(ordinal($0)) exit" } ?? "take the exit"
                let leaving = steps.indices.contains(index + 1) ? steps[index + 1].name : ""
                title = "At the roundabout, \(exit)\(leaving.isEmpty ? "" : " onto \(leaving)")"
                shortTitle = step.exitNumber.map { "\(ordinal($0)) exit" } ?? "Exit"
                shortRoad = shortRoadName(leaving)
                complete = step.endAlong
                exitCoordinate = step.endCoordinate
            case "fork":
                kind = .fork
                title = "Keep \(sideWord) at the fork\(onto)"
                shortTitle = "Keep \(sideWord)"
                complete = step.startAlong
            case "merge":
                kind = .merge
                title = "Merge\(step.turn.side == .straight ? "" : " \(sideWord)")\(onto)"
                shortTitle = step.turn.side == .straight ? "Merge" : "Merge \(sideWord)"
                complete = step.startAlong
            case "on ramp", "off ramp":
                kind = .ramp
                title = step.maneuverType == "on ramp" ? "Take the ramp\(onto)" : "Take the exit\(onto)"
                shortTitle = step.maneuverType == "on ramp" ? "Take ramp" : "Take exit"
                complete = step.startAlong
            case "new name", "continue":
                kind = .keepGoing
                title = "Continue\(onto)"
                shortTitle = "Continue"
                complete = step.startAlong
            default:
                kind = .turn
                title = step.instruction
                switch step.turn.severity {
                case .uTurn: shortTitle = "U-turn"
                case .sharp: shortTitle = "Sharp \(sideWord)"
                case .slight: shortTitle = "Bear \(sideWord)"
                case .normal: shortTitle = step.turn.side == .straight ? "Continue" : "Turn \(sideWord)"
                }
                complete = step.startAlong
            }
            cards.append(GuidanceCard(
                id: index, kind: kind, title: title, shortTitle: shortTitle, shortRoad: shortRoad,
                roadName: road, turn: step.turn, exitNumber: step.exitNumber,
                coordinate: step.intersections.first?.coordinate ?? step.startCoordinate,
                exitCoordinate: exitCoordinate,
                startAlong: step.startAlong, completeAlong: complete, legLength: 0
            ))
        }
        for index in cards.indices {
            let following = index + 1 < cards.count ? cards[index + 1].startAlong : cards[index].completeAlong
            cards[index].legLength = max(0, following - cards[index].completeAlong)
        }
        return cards
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
    let annotation: OSRMAnnotation?
}

/// Per-segment road data OSRM attaches when asked (`annotations=`): each array has one entry per
/// consecutive pair of polyline vertices.
private struct OSRMAnnotation: Decodable {
    let duration: [Double]?
    let speed: [Double]?
}

private struct OSRMStep: Decodable {
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
/// GuidanceLineView applies and logs the actual entry/bearing/name filter stages itself.
private struct OSRMIntersection: Decodable {
    /// [longitude, latitude], per OSRM's convention.
    let location: [Double]
    let bearings: [Int]
    let entry: [Bool]
    let `in`: Int?
    let out: Int?
}

private struct OSRMManeuver: Decodable {
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
private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}
