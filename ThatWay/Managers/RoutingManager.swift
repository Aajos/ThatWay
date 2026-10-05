//
//  RoutingManager.swift
//  ThatWay
//
//  Progress tracking and guidance-card construction against whatever `Route` the current
//  `RoutingProvider` chain returns — never talks to OSRM (or any engine) directly; that's
//  `OSRMRoutingProvider`'s job, behind `RoutingGovernor`'s rate limiting/retry/backoff.
//

import Combine
import CoreLocation
import Foundation

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

    /// Every instruction for the whole trip, built once when the route arrives.
    @Published private(set) var cards: [GuidanceCard] = []
    /// How far (metres) along the route the traveller has got. Everything on the way card —
    /// which instruction is current and how far off it is — comes from this, so it's measured
    /// along the actual road rather than as a straight line, and can't be skipped by a fast
    /// traveller stepping over a proximity circle between two location checks.
    @Published private(set) var progressAlong: Double = 0
    private(set) var routeLength: Double = 0
    /// How far along the route the last *real* fix put the traveller (never goes backward).
    /// `progressAlong` is this plus whatever dead-reckoned distance `projectionExtra` allows.
    private(set) var fixedProgress: Double = 0
    /// Metres of dead-reckoned travel since the last real fix, set by whoever owns the location
    /// (see `DeadReckoning`) before each progress update. 0 = trust the fix as-is.
    var projectionExtra: Double = 0
    /// Keeps the estimate this far short of the end of the route, so only a real fix can arrive.
    var projectionArrivalMargin: Double = 1.5
    /// Per-segment road data along the polyline (one entry per vertex pair, all legs joined):
    /// how long each segment takes and how fast the road is (its profile speed, m/s — from road
    /// class and speed limits, not live traffic). `segmentDurations` is scaled to sum to the
    /// route's own total duration, so junction/turn penalties the engine adds on top of raw
    /// travel time are included. Empty when the engine didn't provide them.
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

    /// The current diagnosis, mirrored from `RoutingGovernor` — non-nil while a fetch or reroute
    /// is retrying (or has given up, for a non-retryable failure). A failed reroute never clears
    /// the route/cards/polyline already on screen; this is purely informational.
    @Published private(set) var currentFailure: RouteFailure?
    @Published private(set) var nextRetryAt: Date?

    /// How far (metres) the traveller can be from the route's snapped start point and still
    /// count as "at the start". The engine snaps the route onto the nearest road it knows about,
    /// which can sit well outside the walking/driving corridor tolerance from a raw coordinate
    /// (an address, a mock GPS fix) — without this, that snap gap alone reads as having already
    /// drifted off a route nobody has taken a step on yet.

    /// The exact `Route` last applied (post destination-extension) — what `RoutePersistence`
    /// saves, rather than a lossy reconstruction from the unpacked `@Published` properties.
    private(set) var currentRoute: Route?
    private let governor: RoutingGovernor
    private var fetchTask: Task<Void, Never>?
    private var activeProfile: TravelProfile = .driving
    private var cancellables = Set<AnyCancellable>()

    var currentStep: RouteStep? { steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil }
    var nextStep: RouteStep? { steps.indices.contains(currentStepIndex + 1) ? steps[currentStepIndex + 1] : nil }
    var isFinished: Bool { !steps.isEmpty && currentStepIndex >= steps.count - 1 }
    var hasRoute: Bool { !steps.isEmpty }

    var remainingDistance: Double { max(0, routeLength - progressAlong) }

    init(provider: RoutingProvider? = nil) {
        let resolvedProvider = provider ?? FallbackRoutingProvider(providers: [OSRMRoutingProvider()])
        governor = RoutingGovernor(provider: resolvedProvider)
        governor.$currentFailure.receive(on: DispatchQueue.main).sink { [weak self] in self?.currentFailure = $0 }.store(in: &cancellables)
        governor.$nextRetryAt.receive(on: DispatchQueue.main).sink { [weak self] in self?.nextRetryAt = $0 }.store(in: &cancellables)
    }

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

    /// Fetches a route for `profile` from `origin` to `destination` and applies it, retrying
    /// through `RoutingGovernor` for as long as this call is awaited — cancel the Task awaiting
    /// this (guidance ending) to give up early. A failed *reroute* leaves whatever route/cards/
    /// polyline already exist completely untouched.
    func getRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile, isReroute: Bool = false) async {
        fetchTask?.cancel()
        isLoading = true
        activeProfile = profile
        let task = Task { [weak self] in
            guard let self else { return }
            let fetched = isReroute
                ? await self.governor.fetchReroute(from: origin, to: destination, profile: profile)
                : await self.governor.fetchInitial(from: origin, to: destination, profile: profile)
            guard !Task.isCancelled else { return }
            if let route = fetched {
                self.apply(route: route, destination: destination)
            }
            self.isLoading = false
        }
        fetchTask = task
        await task.value
    }

    /// Cancels any in-flight fetch/retry loop without touching the route already applied —
    /// call when guidance ends or the traveller comes back on-route mid-reroute.
    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        isLoading = false
        governor.reset()
    }

    func retryNow() { governor.retryNow() }

    /// Rebuilds state from an already-fetched `Route` — no network involved. Used to restore a
    /// trip in progress after a relaunch (`RoutePersistence`).
    func restore(route: Route, destination: CLLocationCoordinate2D, profile: TravelProfile) {
        activeProfile = profile
        apply(route: route, destination: destination)
    }

    func clear() {
        cancelFetch()
        currentRoute = nil
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
        fixedProgress = 0
        projectionExtra = 0
        lastSegmentIndex = 0
        currentFailure = nil
        nextRetryAt = nil
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
        let fixAdvanced = located.along > fixedProgress
        if fixAdvanced { fixedProgress = located.along }
        let target = projectedProgress(base: fixedProgress, extra: projectionExtra, arrivalMargin: projectionArrivalMargin)
        // A new real fix always lands; a projection-only change under a metre isn't worth a redraw.
        if target != progressAlong, fixAdvanced || abs(target - progressAlong) >= 1 { progressAlong = target }
        if let index = steps.lastIndex(where: { $0.startAlong <= progressAlong }), index > currentStepIndex {
            currentStepIndex = index
        }
    }

    /// `base` plus `extra` metres of dead reckoning, held short of the next manoeuvre (and of the
    /// arrival radius) so the current card and arrival only ever change on real fixes — an estimate
    /// that ran ahead and was then corrected could otherwise flip a card forward and back.
    func projectedProgress(base: Double, extra: Double, arrivalMargin: Double) -> Double {
        guard extra > 0 else { return base }
        var limit = routeLength - arrivalMargin
        if let card = cards.first(where: { $0.completeAlong > base + 1 }) {
            switch card.kind {
            case .arrive: limit = card.startAlong - arrivalMargin
            case .roundabout where base >= card.startAlong: limit = card.completeAlong - 1.5
            default: limit = card.startAlong - 1.5
            }
        }
        return max(base, min(base + extra, limit))
    }

    /// Direction of the route segment the traveller is on, for judging whether their course follows it.
    var currentSegmentBearing: CLLocationDirection? {
        guard routePolyline.indices.contains(lastSegmentIndex + 1) else { return nil }
        return CompassManager.bearing(from: routePolyline[lastSegmentIndex], to: routePolyline[lastSegmentIndex + 1])
    }

    /// The point `distance` metres along the route (clamped to its ends).
    func coordinate(atAlong distance: Double) -> CLLocationCoordinate2D? {
        guard routePolyline.count > 1, cumulative.count == routePolyline.count else { return nil }
        let d = max(0, min(distance, routeLength))
        var low = 0, high = cumulative.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= d { low = mid } else { high = mid }
        }
        let span = cumulative[high] - cumulative[low]
        let t = span > 0 ? (d - cumulative[low]) / span : 0
        let a = routePolyline[low], b = routePolyline[high]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// `real` moved on by the dead-reckoned stretch: the same lateral offset from the road, shifted
    /// as far along it as the estimate has carried them. `real` itself when there's no estimate.
    func projectedPosition(from real: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard progressAlong > fixedProgress,
              let from = coordinate(atAlong: fixedProgress), let to = coordinate(atAlong: progressAlong) else { return real }
        return CLLocationCoordinate2D(latitude: real.latitude + (to.latitude - from.latitude),
                                      longitude: real.longitude + (to.longitude - from.longitude))
    }

    /// Called on each `LocationCheckScheduler` poll with the traveller's real (or simulated)
    /// position and current activity: brings progress up to date, trims `remainingPolyline`
    /// down to the road still ahead of them, and flags `isOffRoute` when they've drifted further
    /// than the activity's real corridor tolerance (15m walking, 30m driving) from the planned
    /// line — for whoever owns navigation (AppModel) to fetch a fresh route.
    func updateProgress(userLocation: CLLocationCoordinate2D, activity: TravelMode) {
        guard !routePolyline.isEmpty else {
            remainingPolyline = []
            isOffRoute = false
            return
        }
        advanceProgress(userLocation: userLocation)
        let threshold = activity.tuning.corridorRadius
        guard let routeStartPoint = routePolyline.first else { return }
        let distanceToStart = CompassManager.distance(from: userLocation, to: routeStartPoint)
        if distanceToStart <= activity.tuning.startSnapRadius, progressAlong < 60 {
            isOffRoute = false
            remainingPolyline = routePolyline
        } else if let located = locate(userLocation) {
            isOffRoute = located.distance > threshold
            remainingPolyline = [located.point] + routePolyline.suffix(from: min(located.segment + 1, routePolyline.count))
        }
    }

    // MARK: - Applying a fetched Route

    /// Extends the route's geometry to the real destination when the engine snapped short of it
    /// (a reserve, a car park, a shop set back from the street), patches the arrive step to match,
    /// and builds the cumulative-distance table `locate()` needs. Engine-agnostic — applied to
    /// whatever `Route` any provider returns, not baked into `OSRMRoutingProvider`.
    private static func extendToDestination(_ route: Route, destination: CLLocationCoordinate2D) -> (route: Route, cumulative: [Double]) {
        var geometry = route.geometry
        let roadEnd = geometry.last
        let finalGap = roadEnd.map { CompassManager.distance(from: $0, to: destination) } ?? 0
        let extends = finalGap > 4
        if extends { geometry.append(destination) }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(geometry.count)
        for index in geometry.indices.dropFirst() {
            cumulative.append(cumulative[index - 1] + CompassManager.distance(from: geometry[index - 1], to: geometry[index]))
        }
        let routeEnd = cumulative.last ?? 0

        var steps = route.steps
        var segmentDurations = route.segmentDurations
        var segmentSpeeds = route.segmentSpeeds
        if extends {
            if let lastIndex = steps.indices.last, steps[lastIndex].maneuverType == "arrive" {
                let old = steps[lastIndex]
                steps[lastIndex] = RouteStep(
                    id: old.id, instruction: old.instruction, distance: old.distance, duration: old.duration,
                    name: old.name, maneuverType: old.maneuverType, maneuverModifier: old.maneuverModifier,
                    startCoordinate: old.startCoordinate, endCoordinate: destination, bearing: old.bearing,
                    intersections: old.intersections, startAlong: routeEnd, endAlong: routeEnd,
                    startIndex: geometry.count - 1, endIndex: geometry.count - 1,
                    turn: old.turn, exitNumber: old.exitNumber, exitBearing: old.exitBearing
                )
            }
            // The last stretch is on foot from the road end.
            if !segmentDurations.isEmpty {
                segmentDurations.append(finalGap / 1.4)
                segmentSpeeds.append(1.4)
            }
        }

        let extended = Route(
            geometry: geometry, distance: route.distance, duration: route.duration, steps: steps,
            segmentDurations: segmentDurations, segmentSpeeds: segmentSpeeds
        )
        return (extended, cumulative)
    }

    private func apply(route: Route, destination: CLLocationCoordinate2D) {
        let (finalRoute, cumulativeTable) = Self.extendToDestination(route, destination: destination)
        currentRoute = finalRoute
        steps = finalRoute.steps
        cards = Self.buildCards(from: finalRoute.steps)
        routePolyline = finalRoute.geometry
        cumulative = cumulativeTable
        segmentDurations = finalRoute.segmentDurations
        segmentSpeeds = finalRoute.segmentSpeeds
        routeLength = cumulativeTable.last ?? 0
        remainingPolyline = finalRoute.geometry
        isOffRoute = false
        totalDistance = finalRoute.distance
        totalDuration = finalRoute.duration
        currentStepIndex = 0
        progressAlong = 0
        fixedProgress = 0
        projectionExtra = 0
        lastSegmentIndex = 0
    }

    // MARK: - Guidance cards

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

    /// "Lakewood Drive" → "Lakewood Dr", "Burwood Highway" → "Burwood Hwy": the common road-type words
    /// abbreviated, so road names fit a card line.
    static func shortRoadName(_ name: String) -> String {
        let table = ["Road": "Rd", "Street": "St", "Drive": "Dr", "Highway": "Hwy", "Avenue": "Ave", "Boulevard": "Blvd",
                     "Court": "Ct", "Crescent": "Cres", "Lane": "Ln", "Place": "Pl", "Parade": "Pde", "Terrace": "Tce",
                     "Freeway": "Fwy", "Circuit": "Cct", "Esplanade": "Esp", "Grove": "Gr", "Close": "Cl"]
        return name.split(separator: " ").map { table[String($0)] ?? String($0) }.joined(separator: " ")
    }

    /// One card per real instruction, for the whole route. "Exit roundabout" steps are folded
    /// into their roundabout's card.
    private static func buildCards(from steps: [RouteStep]) -> [GuidanceCard] {
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
                let heading = step.exitBearing.map { "Head \(cardinal($0))" } ?? "Head out"
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
}
