//
//  AppModel.swift
//  ThatWay
//
//  Simulated navigation state driving the Compass Nav concept screens.
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

@MainActor
final class AppModel: ObservableObject {
    // Navigation
    @Published var screen: AppScreen = .compass
    @Published var mode: NavMode = .point
    @Published var skin: SkinID = .needle
    @Published var theme: ThemeID = .ember
    @Published var lastDark: ThemeID = .ember
    @Published var ownedSkins: Set<SkinID> = [.needle, .wheel, .clock]
    @Published var ownedAvatars: Set<AvatarID> = [.initials, .dot, .ring]
    @Published var avatar: AvatarID = .initials
    @Published var avatarSheet = false
    @Published var searchOpen = false
    @Published var searchQuery = ""
    @Published var dest = ""
    @Published var destKind: DestKind = .none
    /// Past destinations, newest first, each with the real coordinate it resolved to — so
    /// tapping one goes straight to that exact place instead of re-geocoding a bare name
    /// (which could fail, or land on a different same-named place). Persisted across launches.
    @Published var recentSearches: [RecentPlace] = AppModel.loadRecents() {
        didSet { AppModel.saveRecents(recentSearches) }
    }

    // Real routing (OSRM) and real location (CoreLocation via LocationManager).
    // `simulatedPosition` is only a fallback walker — used in place of a real GPS fix when
    // running in the Simulator without a simulated location, or before permission is
    // granted — everything that needs "where the user is" should read `currentPosition`,
    // which prefers the real fix. There's no mock destination anymore: the app opens idle,
    // with nothing selected, until a real search result is picked.
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var simulatedPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    let routingManager = RoutingManager()
    let locationManager = LocationManager()
    let routeDataGenerator = RouteDataGenerator()
    let locationCheckScheduler = LocationCheckScheduler()

    /// The position/speed the guidance corridor check last actually looked at — updated
    /// only by `performLocationCheck()`, i.e. once per adaptive poll (10s walking, 3s
    /// driving), not continuously. `GuidanceLineView`'s look-ahead reads these rather than
    /// the live `currentPosition`/`speedKmh`, so its geometry only recomputes as often as
    /// the corridor check itself actually runs.
    @Published private(set) var guidanceCheckPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    @Published private(set) var guidanceCheckSpeedKmh: Double = 0
    /// True once within 100m of the destination — shows the completion screen. Reset
    /// whenever a fresh guidance session starts or the destination is dismissed.
    @Published var arrived = false

    static let mockUserLocation = CLLocationCoordinate2D(latitude: -37.8941463, longitude: 145.2916477) // 58 Glenfern Road, Ferntree Gully

    // Idle ambient animation tick — purely cosmetic (drives `sway`, a subtle needle
    // wobble at rest); never used to fake a position, speed, or distance reading.
    @Published var t = 0

    // Profile
    @Published var vis: Visibility = .friends
    @Published var closeKm: Double = 8
    /// Which mode picking a destination (a search result) drops straight into.
    /// Point mode is a straight-line bearing with no live route tracking — cheap on
    /// battery. Guidance keeps fetching/baking real turn-by-turn data continuously, which
    /// costs more power for a smoother, corridor-aware experience. Explicit "route there"
    /// actions (the ROUTE button, a map-tap confirmation) always start guidance regardless
    /// of this — it only governs what picking a destination defaults to.
    @Published var defaultNavMode: NavMode = .point

    @Published var opts = NavOptions()


    /// Full tilt (at a turn) for the "Compass tilt" setting, in degrees: Off, Mild, Aggressive.
    var maxTiltDegrees: Double {
        switch opts.tilt {
        case "Off": return 0
        case "Mild": return 15
        default: return 30
        }
    }

    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.09, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        locationManager.requestPermission()
    }

    func tick() {
        t += 1
        // Purely cosmetic per-tick work only — the fallback walker's own position needs
        // smooth 90ms-scale movement to look like real motion in the Simulator. Anything
        // that actually costs something (corridor/off-route checks, reroute fetches) is no
        // longer here: it runs exclusively from `locationCheckScheduler`'s adaptive poll,
        // not on every tick.
        if guiding, !hasRealLocation, routingManager.hasRoute {
            advanceFallbackWalker()
        }
    }

    /// How far the simulated traveller has walked along the current route's real geometry
    /// (`routingManager.routePolyline`), in metres. Reset whenever guidance (re)starts.
    private var routeProgressMeters: Double = 0

    /// A fixed walking pace (m/s) for the fallback traveller below — used only to move it
    /// along real route geometry when there's no real GPS fix at all. It never feeds the
    /// UI's displayed speed or activity badge, which always read the real
    /// `locationManager.speed` (zero when there's no fix), so nothing shown on screen is
    /// ever a forged reading.
    private static let fallbackWalkSpeed: Double = 1.4

    /// Moves the fallback traveller a little further along the route's real geometry each
    /// tick, for smooth visual motion while developing without a device. This is *only*
    /// ever position bookkeeping — it does not check the route, flag off-route, or trigger
    /// a reroute; `performLocationCheck()` does all of that, on its own adaptive schedule.
    private func advanceFallbackWalker() {
        let polyline = routingManager.routePolyline
        guard !polyline.isEmpty else { return }
        let tickInterval = 0.09
        routeProgressMeters += Self.fallbackWalkSpeed * tickInterval
        if let point = CompassManager.pointAlong(polyline, distance: routeProgressMeters) {
            simulatedPosition = point
        }
    }

    /// The actual guidance work — corridor check, off-route flag, reroute trigger, arrival
    /// detection, and the look-ahead snapshot `GuidanceLineView` reads — run from here, and
    /// only from here, on `locationCheckScheduler`'s adaptive cadence (10s walking, 3s
    /// driving) instead of continuously. This is the whole point of the scheduler: the
    /// expensive part of guidance now runs a few times a minute instead of ~11 times a
    /// second.
    private func performLocationCheck() {
        guidanceCheckPosition = currentPosition
        guidanceCheckSpeedKmh = speedKmh
        routingManager.updateProgress(userLocation: currentPosition, activity: guidanceActivity)
        checkArrival()
        // Skips a pointless reroute fetch for a route that's about to be torn down anyway.
        guard !arrived else { return }
        rerouteIfOffRoute()
    }

    /// How close (metres) counts as "arrived" — deliberately generous (100m) rather than
    /// RoutingManager's own tighter per-step `arrivalRadius`, since this is about ending the
    /// whole trip, not just advancing to the next turn instruction.
    private static let arrivalDistance: CLLocationDistance = 100

    /// Once within `arrivalDistance` of the actual destination: stop polling, drop the now-
    /// pointless baked guidance data, and show the completion screen — there's nothing left
    /// for guidance to compute once the trip is over.
    private func checkArrival() {
        guard guiding, !arrived, let destinationCoordinate else { return }
        guard CompassManager.distance(from: currentPosition, to: destinationCoordinate) < Self.arrivalDistance else { return }
        print("[AppModel] Arrived at destination")
        arrived = true
        routeDataGenerator.clearGuidanceData()
        locationCheckScheduler.stop()
    }

    private var lastRerouteAt: Date?
    /// Minimum time between reroute fetches. Without this, a persistent off-route reading
    /// (e.g. a route origin that OSRM snapped to a road some distance from the raw
    /// coordinate, which no amount of re-fetching fixes) would refire every single tick and
    /// hammer the routing API in a tight loop.
    private let rerouteCooldown: TimeInterval = 8

    /// If the traveller has drifted off the planned route (a wrong turn, or a real GPS fix
    /// that's left the road), fetch a fresh route from wherever they actually are now,
    /// rather than leaving them staring at a line that no longer matches where they're
    /// going. Guarded on `isLoading` (no piling up while a fetch is in flight) and a cooldown
    /// (no refetching every tick if the reading stays off-route regardless).
    private func rerouteIfOffRoute() {
        guard routingManager.isOffRoute, !routingManager.isLoading, let destinationCoordinate else { return }
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < rerouteCooldown { return }
        lastRerouteAt = Date()
        print("[AppModel] Off route — fetching a fresh route from the current position")
        // Stopped here and restarted once the new route lands in `fetchRoute` below — the
        // old route's corridor is invalid for the length of the fetch, so there's nothing
        // useful for a check to run against in between.
        locationCheckScheduler.stop()
        fetchRoute(to: destinationCoordinate, isReroute: true)
    }

    // MARK: - Derived state

    var currentTheme: AppTheme { AppTheme.byId(theme) }
    var guiding: Bool { mode == .guidance }

    /// Where the user actually is: the real GPS fix once one's available, else the
    /// fallback mock walker. Everything that needs "where am I" should read this, not
    /// `simulatedPosition` directly.
    var currentPosition: CLLocationCoordinate2D { locationManager.coordinate ?? simulatedPosition }
    var hasRealLocation: Bool { locationManager.coordinate != nil }
    /// The device's real compass heading once it's reliable, else 0 (screen-up as a
    /// stand-in "north") — matches the old fixed behaviour until a real heading arrives.
    var currentHeading: CLLocationDirection { locationManager.hasReliableHeading ? locationManager.heading : 0 }

    /// Idle: not guiding, and no place selected to point at. The dial goes
    /// north-up and flat, with the cardinal markers emphasized, so it's unmistakably at rest.
    var isIdle: Bool { !guiding && destKind == .none }
    /// A subtle idle-only needle wobble — cosmetic "alive" motion, not a stand-in for any
    /// real position, speed, or direction reading.
    var sway: Double { sin(Double(t) / 11) * 9 }

    /// True once a real OSRM route has been fetched for the current destination — driving
    /// the turn card and needle with actual turn-by-turn data instead of a straight line.
    var hasRealRoute: Bool { routingManager.hasRoute }

    /// Straight-line distance from the user's current position to the step's endpoint.
    var distanceToManeuver: Double {
        guard let coordinate = routingManager.currentStep?.endCoordinate else { return 0 }
        return CompassManager.distance(from: currentPosition, to: coordinate)
    }

    /// Real distance to whatever's currently relevant: the next turn while a route is
    /// loaded and guiding, otherwise a straight line to the destination. Zero when there's
    /// nothing selected — never a simulated countdown.
    var activeDist: Double {
        if guiding, hasRealRoute { return distanceToManeuver }
        if let destinationCoordinate { return CompassManager.distance(from: currentPosition, to: destinationCoordinate) }
        return 0
    }

    var far: Double {
        if guiding, hasRealRoute, let metres = routingManager.currentStep?.distance {
            return max(0, min(1, distanceToManeuver / max(metres, 1)))
        }
        return max(0, min(1, activeDist / (guiding ? 500 : 1200)))
    }

    /// The turn card's headline: the real OSRM instruction once a route is loaded,
    /// otherwise a loading/error message, or a plain "head toward X" while the route
    /// is still being fetched.
    var turnCopy: String {
        if routingManager.isLoading { return "Finding your route…" }
        if let error = routingManager.errorMessage { return error }
        if guiding, hasRealRoute { return routingManager.currentStep?.instruction ?? "You've arrived" }
        return dest.isEmpty ? "Head toward your destination" : "Head toward \(dest)"
    }

    var turnSubtitle: String {
        if guiding, hasRealRoute { return "\(fmt(distanceToManeuver)) to go" }
        if let destinationCoordinate {
            return "\(fmt(CompassManager.distance(from: currentPosition, to: destinationCoordinate))) straight-line"
        }
        return ""
    }

    var turnDir: TurnDir {
        guard guiding, hasRealRoute else { return .straight }
        return routingManager.currentStep?.turnDirection ?? .straight
    }

    /// The next real turn's OSRM modifier ("left", "sharp right", "uturn", …) once it's within
    /// range — 300m standing still, stretching to 1km at 100 km/h, since faster travel needs
    /// earlier warning. Nil on a straight run, when there's no route, or at arrival.
    var upcomingTurnModifier: String? {
        guard guiding, hasRealRoute, let upcoming = routingManager.nextStep,
              upcoming.maneuverType != "arrive",
              distanceToManeuver <= 300 + min(1, speedKmh / 100) * 700,
              let modifier = upcoming.maneuverModifier,
              modifier.contains("left") || modifier.contains("right") else { return nil }
        return modifier
    }

    /// The arrow beside the distance readout: straight up by default, then a bend in the
    /// upcoming turn's direction, or a U-turn arrow for sharp turns and U-turns.
    var dialArrowSymbol: String {
        guard let modifier = upcomingTurnModifier else { return "arrow.up" }
        let side = modifier.contains("left") ? "left" : "right"
        switch modifier {
        case "uturn", "sharp left", "sharp right": return "arrow.uturn.\(side)"
        case "slight left", "slight right": return "arrow.up.\(side)"
        default: return "arrow.turn.up.\(side)"
        }
    }

    /// How far to rotate the dial's cardinal ring (the tick marks and N/E/S/W letters) so
    /// "N" always sits at true geographic north on screen as the phone turns — a real
    /// rotating compass bezel, independent of the needle. The needle keeps pointing at the
    /// destination via `needleDeg`, which is already screen-relative (bearing minus
    /// heading), so the two rotate independently and only agree when the destination
    /// itself lies due north.
    var dialHeadingDeg: Double { CompassManager.relativeBearing(heading: currentHeading, bearing: 0) }

    var needleDeg: Double {
        // Idle: no destination selected — point at true north (same math as the dial's own
        // north marker), so needle and dial visibly agree instead of the needle freezing
        // at a fake straight-up regardless of which way the phone is actually facing.
        if isIdle { return dialHeadingDeg }
        // Point the needle at the real bearing from wherever the traveller actually is
        // right now toward the next turn (guidance with a loaded route) — converging on
        // the real destination itself once the final step is reached — or toward the
        // destination directly otherwise, whenever we have a real coordinate for it.
        if guiding, hasRealRoute {
            let target = routingManager.isFinished ? destinationCoordinate : routingManager.currentStep?.endCoordinate
            if let target {
                let bearing = CompassManager.bearing(from: currentPosition, to: target)
                return CompassManager.relativeBearing(heading: currentHeading, bearing: bearing) + sway * 0.15
            }
        }
        if let destinationCoordinate {
            let bearing = CompassManager.bearing(from: currentPosition, to: destinationCoordinate)
            return CompassManager.relativeBearing(heading: currentHeading, bearing: bearing) + sway * (guiding ? 0.15 : 0.3)
        }
        return sway
    }

    /// Fully flat at rest in idle mode — no lean at all, so the dial visibly settles.
    var tiltDeg: Double { isIdle ? 0 : far * maxTiltDegrees }
    /// Sideways lean into the upcoming turn (same turn the dial arrow shows): a little for a slight
    /// bend, more for a full turn, most for a sharp turn or U-turn — scaled by the "Compass tilt"
    /// setting (Off = none, Mild = 60%).
    var laneDeg: Double {
        guard let modifier = upcomingTurnModifier else { return 0 }
        let strength: Double
        switch opts.tilt {
        case "Off": return 0
        case "Mild": strength = 0.6
        default: strength = 1
        }
        let magnitude: Double
        switch modifier {
        case "uturn", "sharp left", "sharp right": magnitude = 16
        case "slight left", "slight right": magnitude = 7
        default: magnitude = 13
        }
        return (modifier.contains("left") ? -1 : 1) * magnitude * strength
    }

    /// Real speed over ground from CoreLocation, in km/h — zero whenever there's no real
    /// GPS fix, never a simulated number.
    var speedKmh: Double { max(0, locationManager.speed) * 3.6 }
    /// `speedKmh` converted to the unit the user picked in Settings.
    var displaySpeed: Double { opts.units == "Miles" ? speedKmh * 0.621371 : speedKmh }
    /// Under 8 km/h is walking, 8–20 is running, above 20 is driving.
    var auto: String { speedKmh < 8 ? "WALKING" : speedKmh < 20 ? "RUNNING" : "DRIVING" }
    var activity: String { opts.activity == "Automatic" ? auto : opts.activity.uppercased() }
    /// `activity` collapsed to the two-state corridor/polling profile everything guidance-
    /// related actually keys off — "RUNNING" gets walking's tighter tolerance, since a
    /// runner drifts about as far from a path as a walker does.
    var guidanceActivity: GuidanceActivity { activity == "DRIVING" ? .driving : .walking }

    /// True at walking pace or below where "walking" stops being a meaningful label —
    /// under 2 km/h is standing still (or GPS noise on a stationary phone), not actually
    /// walking anywhere. Display-only: doesn't affect `activity`/`guidanceActivity`, which
    /// still need a real walking/running/driving classification for corridor tolerance and
    /// route colour regardless of whether the label shown right now says "stationary".
    var isStationary: Bool { speedKmh <= 2 }
    var activityDisplayLabel: String { isStationary ? "STATIONARY" : activity }

    /// The route line's colour, blended continuously from the real speed rather than
    /// snapping between fixed colours at the walk/run/drive boundaries — green through
    /// amber to blue, smoothly, across bands centred on the 8 and 20 km/h thresholds.
    var routeColor: Color {
        let walk = Color(hex: "2FCF9B")
        let run = Color(hex: "FFB020")
        let drive = Color(hex: "3B82F6")
        let kmh = speedKmh
        switch kmh {
        case ..<5: return walk
        case 5..<11: return .lerp(walk, run, (kmh - 5) / 6)
        case 11..<17: return run
        case 17..<23: return .lerp(run, drive, (kmh - 17) / 6)
        default: return drive
        }
    }

    var accent: Color { currentTheme.accent }

    /// The 2-3 tones the dial's glass rim gradient pulls from.
    var dialGlassColors: [Color] {
        [currentTheme.accent, Color(hex: "34D6A5"), currentTheme.accent.hueShifted(24)]
    }

    var currentAvatar: AvatarOption { AvatarOption.byId(avatar) }
    var currentSkin: Skin { Skin.byId(skin) }

    func fmt(_ m: Double) -> String { CompassGeometry.fmt(m) }
    func aud(_ n: Double) -> String { CompassGeometry.aud(n) }

    // MARK: - Actions

    func flipMode() {
        if mode == .point {
            startGuidance()
        } else {
            endGuidance()
        }
    }

    /// Fetches (or clears) the real OSRM route for `destination` from wherever the user
    /// actually is right now. Drives both the guidance turn card and the route-preview
    /// line shown on the Map tab, so a route appears as soon as a destination exists —
    /// not just once guidance formally starts. When this fetch is happening because guidance
    /// is actually active, it also bakes (or, for a reroute, re-bakes) `RouteDataGenerator`'s
    /// guidance data once the route arrives — never for a plain Point-mode preview.
    private func fetchRoute(to destination: CLLocationCoordinate2D?, isReroute: Bool = false) {
        guard let destination else { routingManager.clear(); return }
        let origin = currentPosition
        Task {
            await routingManager.getRoute(from: origin, to: destination)
            guard guiding, routingManager.hasRoute, !arrived else { return }
            if isReroute {
                routeDataGenerator.regenerateGuidanceData(
                    polyline: routingManager.routePolyline, steps: routingManager.steps, activity: guidanceActivity
                )
                // The reroute fetch is done and the new route is baking — resume polling
                // against it. `start` is idempotent, so this is also harmless on the very
                // first fetch (isReroute: false), where the scheduler was already started
                // synchronously in `startGuidance()` below and just keeps running. Guarded
                // on `!arrived` above: this fetch could have been in flight when a later
                // check already detected arrival and stopped the scheduler — without that
                // guard, this completion would silently restart it right afterward.
                startLocationChecks()
            } else {
                routeDataGenerator.generateGuidanceData(
                    polyline: routingManager.routePolyline, steps: routingManager.steps, activity: guidanceActivity
                )
            }
        }
    }

    /// Starts (or resumes) `locationCheckScheduler` for the current mode/activity, and runs
    /// one check immediately rather than waiting out a full interval before the guidance
    /// line has anything real to show.
    private func startLocationChecks() {
        locationCheckScheduler.start(
            mode: mode,
            activityProvider: { [weak self] in self?.guidanceActivity ?? .walking },
            onCheck: { [weak self] in self?.performLocationCheck() }
        )
    }

    func startGuidance() {
        mode = .guidance
        routeProgressMeters = 0
        lastRerouteAt = nil
        arrived = false
        simulatedPosition = Self.mockUserLocation
        fetchRoute(to: destinationCoordinate)
        startLocationChecks()
        performLocationCheck()
    }

    func endGuidance() {
        mode = .point
        routeProgressMeters = 0
        arrived = false
        routeDataGenerator.clearGuidanceData()
        locationCheckScheduler.stop()
        // The route itself stays put — the destination is still selected, so the Map tab
        // keeps showing the preview line until the user picks something new or clears it.
    }

    func setTheme(_ id: ThemeID) {
        let th = AppTheme.byId(id)
        theme = id
        if !th.light { lastDark = id }
    }

    func toggleTheme() {
        setTheme(currentTheme.light ? lastDark : .paper)
    }

    /// After a destination coordinate is set, starts navigating to it in whichever mode the
    /// user picked as their default (You page) — Guidance jumps straight into turn-by-turn,
    /// Point just previews the route line and waits for an explicit ROUTE tap. Explicit
    /// "route there" actions elsewhere (the ROUTE button, a map-tap confirmation) bypass
    /// this and always call `startGuidance()` directly.
    private func beginNavigatingToDestination() {
        if defaultNavMode == .guidance {
            startGuidance()
        } else {
            mode = .point
            fetchRoute(to: destinationCoordinate)
        }
    }

    /// Drops whatever place is selected and returns the compass to idle:
    /// north-up, flat, cardinal markers emphasized.
    func clearDestination() {
        destKind = .none
        dest = ""
        destinationCoordinate = nil
        routingManager.clear()
    }

    func pickPlace(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dest = trimmed
        destKind = .place
        searchOpen = false
        searchQuery = ""

        // No coordinate yet — nothing to navigate to until the real geocode below resolves.
        // Point mode just sits with the name shown and no bearing until then; Guidance
        // mode's own fetch below is a no-op (`fetchRoute` clears on a nil destination) until
        // the real coordinate arrives and triggers the actual first fetch.
        destinationCoordinate = nil
        beginNavigatingToDestination()
        let origin = currentPosition
        Task { [weak self] in
            guard let self, let real = await PlaceSearch.firstResult(for: trimmed, near: origin) else { return }
            guard self.dest == trimmed else { return } // a newer search superseded this one
            self.destinationCoordinate = real
            self.remember(name: trimmed, coordinate: real)
            // Corrects whichever mode is already active (Point preview or live Guidance)
            // with the real coordinate — a reroute in spirit, even though it's a geocode
            // correction rather than the traveller actually drifting off the road.
            self.fetchRoute(to: real, isReroute: true)
        }
    }

    /// Selects a destination straight from a real search result — already has a real
    /// coordinate, so no geocoding round-trip is needed before showing it.
    func pickPlace(mapItem: MKMapItem) {
        let name = mapItem.name ?? "Selected place"
        dest = name
        destKind = .place
        searchOpen = false
        searchQuery = ""
        remember(name: name, coordinate: mapItem.placemark.coordinate)

        destinationCoordinate = mapItem.placemark.coordinate
        beginNavigatingToDestination()
    }

    /// Picks a past destination using the coordinate it was saved with — no geocoding
    /// round-trip, so it can't fail or resolve to a different place.
    func pickRecent(_ place: RecentPlace) {
        dest = place.name
        destKind = .place
        searchOpen = false
        searchQuery = ""
        remember(name: place.name, coordinate: place.coordinate)
        destinationCoordinate = place.coordinate
        beginNavigatingToDestination()
    }

    private func remember(name: String, coordinate: CLLocationCoordinate2D) {
        var updated = recentSearches
        updated.removeAll { $0.name == name }
        updated.insert(RecentPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude), at: 0)
        recentSearches = Array(updated.prefix(5))
    }

    private static let recentsKey = "recentSearches.v1"
    private static func loadRecents() -> [RecentPlace] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let decoded = try? JSONDecoder().decode([RecentPlace].self, from: data) else { return [] }
        return decoded
    }
    private static func saveRecents(_ recents: [RecentPlace]) {
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    /// A notable named spot tapped on the Map tab — either one of our own real nearby-place
    /// markers or a built-in Apple Maps point of interest — waiting on the user to confirm
    /// whether they actually want to be routed there.
    struct MapSelectionPrompt: Identifiable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D
    }
    @Published var mapSelectionPrompt: MapSelectionPrompt?

    /// Called when the user taps a notable named location on the Map tab. Autofills the
    /// search bar with its name, switches to the Compass screen, and surfaces a prompt
    /// asking whether to route there — rather than silently starting guidance on a tap that
    /// might have been exploratory.
    func selectMapFeature(name: String, coordinate: CLLocationCoordinate2D) {
        searchQuery = name
        screen = .compass
        mapSelectionPrompt = MapSelectionPrompt(name: name, coordinate: coordinate)
    }

    /// The user confirmed the "route there?" prompt — selects the tapped location as the
    /// destination and jumps straight into guidance, exactly like tapping ROUTE would.
    func confirmMapSelectionRouting() {
        guard let prompt = mapSelectionPrompt else { return }
        dest = prompt.name
        destKind = .place
        searchOpen = false
        searchQuery = ""
        destinationCoordinate = prompt.coordinate
        remember(name: prompt.name, coordinate: prompt.coordinate)
        mapSelectionPrompt = nil
        startGuidance()
    }

    /// The user declined the prompt — the search bar keeps showing the autofilled name, but
    /// nothing further happens.
    func dismissMapSelectionPrompt() {
        mapSelectionPrompt = nil
    }

    func pickSkin(_ id: SkinID) {
        if ownedSkins.contains(id) {
            skin = id
            screen = .compass
        } else {
            ownedSkins.insert(id)
            skin = id
        }
    }

    func pickAvatar(_ id: AvatarID) {
        if ownedAvatars.contains(id) {
            avatar = id
        } else {
            ownedAvatars.insert(id)
            avatar = id
        }
    }

    func goDonate() {
        screen = .store
    }

    func selectTab(_ s: AppScreen) {
        screen = s
        searchOpen = false
        avatarSheet = false
    }

}
