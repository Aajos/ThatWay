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
    @Published var mode: NavMode = .point {
        didSet { updateBackgroundTracking() }
    }
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

    // `fallbackPosition` is a fixed, non-moving placeholder used only before the first real GPS
    // fix (or in the Simulator with no simulated location set). It never moves: all movement
    // comes from real or Simulator-injected location updates. Everything that needs "where the
    // user is" should read `currentPosition`,
    // granted — everything that needs "where the user is" should read `currentPosition`,
    // which prefers the real fix. There's no mock destination anymore: the app opens idle,
    // with nothing selected, until a real search result is picked.
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    private let fallbackPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    let routingManager: RoutingManager
    let locationManager = LocationManager()
    let routeDataGenerator = RouteDataGenerator()
    let etaManager = ETAManager()
    let locationCheckScheduler = LocationCheckScheduler()
    let authManager = AuthManager()
    lazy var friendsManager = FriendsManager(auth: authManager)

    /// The position/speed the guidance corridor check last actually looked at — updated
    /// only by `performLocationCheck()`, i.e. once per adaptive poll (10s walking, 3s
    /// driving), not continuously. `GuidanceLineView`'s look-ahead reads these rather than
    /// the live `currentPosition`/`speedKmh`, so its geometry only recomputes as often as
    /// the corridor check itself actually runs.
    @Published private(set) var guidanceCheckPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    @Published private(set) var guidanceCheckSpeedKmh: Double = 0
    /// True once within 100m of the destination — shows the completion screen. Reset
    /// whenever a fresh guidance session starts or the destination is dismissed.
    @Published var arrived = false {
        didSet { updateBackgroundTracking() }
    }

    static let mockUserLocation = CLLocationCoordinate2D(latitude: -37.8941463, longitude: 145.2916477) // 58 Glenfern Road, Ferntree Gully


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


    private var timer: AnyCancellable?

    init(routingManager: RoutingManager? = nil) {
        self.routingManager = routingManager ?? RoutingManager()
        audioManager.style = audioStyle
        startTick()
        // With the screen off the tick is paused, so guidance state keeps moving from location
        // updates instead (delivered a moment after the value changes, hence the main-queue hop).
        locationManager.$location
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.locationDidUpdate() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.lowPowerChanged() }
            .store(in: &cancellables)
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #if PERF
        objectWillChange.sink { Perf.hit("appPublish") }.store(in: &cancellables)
        locationManager.objectWillChange.sink { Perf.hit("locMgrPublish") }.store(in: &cancellables)
        self.routingManager.objectWillChange.sink { Perf.hit("routingPublish") }.store(in: &cancellables)
        #endif
        // Permission / precision changes are rare, and the "location issue" card reads them, so they
        // republish. (Fixes themselves deliberately don't — see `locationDidUpdate`.)
        // Speed shows in the top bar and nothing else republishes while idle; it changes at fix rate.
        // (Heading is deliberately NOT forwarded here: the dial observes the location manager itself, so
        // a heading change redraws only the dial, not the whole screen.)
        locationManager.$speed
            .dropFirst()
            .removeDuplicates()
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        locationManager.$authorizationStatus.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        locationManager.$isReducedAccuracy.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        locationManager.requestPermission()
        restorePersistedTrip()
        refreshLocationProfile()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Power

    /// Low Power Mode: the cosmetic tick slows to 4 Hz and the location profile relaxes (wider
    /// distance filter, coarser heading, no better than 10 m accuracy).
    private(set) var lowPower = false
    /// One tick a second is all anything needs now: the once-a-second guidance refresh. (The needle
    /// sway and aura breathing are implicit animations inside the dial, so they cost no app CPU.)
    /// 1 s while guiding (the once-a-second refresh); 3 s otherwise, when the tick only has the compass
    /// health check and the stationary-GPS check to do.
    private var tickInterval: TimeInterval { (guiding ? 1.0 : 3.0) * (lowPower ? 2 : 1) }
    private var lastLocationAt = Date()
    private var lastTickInterval: TimeInterval = 1

    private func lowPowerChanged() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if sceneActive { startTick() }
        refreshLocationProfile()
    }

    /// Picks the CoreLocation accuracy / distance filter / heading filter for what the app is doing
    /// right now. Cheap and idempotent: `LocationManager.apply` ignores an unchanged profile.
    private func refreshLocationProfile() {
        let stationary = Date().timeIntervalSince(lastLocationAt) > LocationProfile.stationaryAfter
        let profile = LocationProfile.make(
            mode: travelMode,
            guiding: guiding && !arrived,
            hasDestination: destinationCoordinate != nil,
            distanceToNextTurn: guiding && hasRealRoute && !arrived ? distanceToManeuver : nil,
            stationary: stationary,
            lowPower: lowPower
        )
        locationManager.apply(profile)
    }

    // MARK: - Screen on / off

    /// False once the app leaves the foreground (screen locked, another app on top). Guidance
    /// itself carries on in the background; everything that only exists to animate the screen
    /// — the 11 Hz cosmetic tick and the compass heading — is switched off until it's back.
    private(set) var sceneActive = true
    private var lastGuidanceRefresh = Date.distantPast

    func setSceneActive(_ active: Bool) {
        guard active != sceneActive else { return }
        sceneActive = active
        updateScreenAwake()
        if active {
            startTick()
            locationManager.setHeadingActive(true)
            refreshGuidanceState()
        } else {
            timer = nil
            locationManager.setHeadingActive(false)
            // Samples from before the screen went off say nothing about the compass afterwards.
            compassHealth.reset()
            if compassSuspect { compassSuspect = false; compassPredicted = nil }
            usingGPSHeading = false
        }
    }

    private func startTick() {
        guard Perf.on("tick") else { timer = nil; return }
        lastTickInterval = tickInterval
        timer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func locationDidUpdate() {
        Perf.hit("locDeliver")
        Perf.stamp("locGap")
        lastLocationAt = Date()
        guard !sceneActive, Date().timeIntervalSince(lastGuidanceRefresh) >= 1 else { return }
        refreshGuidanceState()
    }

    /// Background location only runs while a trip is being guided and hasn't ended in arrival.
    private func updateBackgroundTracking() {
        locationManager.setBackgroundGuidance(guiding && !arrived, activityType: travelMode.locationActivityType)
        refreshLocationProfile()
        updateScreenAwake()
        if sceneActive, timer != nil, abs(tickInterval - lastTickInterval) > 0.01 { startTick() }
    }

    /// While a trip is being guided and the app is on screen, the display stays on — the compass is
    /// something you glance at mid-walk, and an auto-locking screen would hide it every 30 seconds.
    /// Locking the phone yourself still works: guidance carries on in the background with audio cues.
    private func updateScreenAwake() {
        let awake = guiding && !arrived && sceneActive
        if UIApplication.shared.isIdleTimerDisabled != awake { UIApplication.shared.isIdleTimerDisabled = awake }
    }

    func tick() {
        Perf.hit("tick")
        // Anything that actually costs something (corridor/off-route checks, reroute fetches)
        // runs exclusively from `locationCheckScheduler`'s adaptive poll, not on every tick.
        refreshGuidanceState()
    }

    /// Which instruction is current, how far off it is, arrival, ETA and the compass tilt stages,
    /// re-derived from the traveller's real position about once a second — cheap (a windowed
    /// nearest-point search), and independent of the slower corridor/off-route poll — so the way
    /// card can never lag a long way behind the road. Driven by the tick while the screen is on
    /// and by location updates while it's off.
    private func refreshGuidanceState() {
        guard Perf.on("refresh") else { return }
        Perf.hit("refresh")
        lastGuidanceRefresh = Date()
        Perf.stamp("refreshGap")
        updateProjection()
        if sceneActive { updateCompassHealth() }
        if guiding, routingManager.hasRoute, !arrived {
            if Perf.on("advance") { routingManager.advanceProgress(userLocation: currentPosition) }
            if Perf.on("arrival") { checkArrival() }
            if Perf.on("bake") { bakeRouteLineIfNeeded() }
            if Perf.on("eta") { etaManager.update(routing: routingManager, speedKmh: speedKmh, activity: travelMode) }
            if Perf.on("audio") { announceIfDue() }
        }
        if Perf.on("tilt") { updateTiltStages() }
        if Perf.on("locprofile") { refreshLocationProfile() }
    }

    /// Dead reckoning (see `DeadReckoning`): how far the traveller has probably got along the route since
    /// the last GPS fix. Only guidance *display* state uses it — the cards, distances, ETA, audio cues
    /// and needle. Off-route detection and arrival always use the real fix.
    private func updateProjection() {
        var extra = 0.0
        if Perf.on("deadreckon"), guiding, !arrived, routingManager.hasRoute, !routingManager.isOffRoute,
           let fix = locationManager.location {
            extra = DeadReckoning.extraMetres(
                speed: fix.speed, course: fix.course, routeBearing: routingManager.currentSegmentBearing,
                age: Date().timeIntervalSince(fix.timestamp), distanceCap: locationManager.activeDistanceFilter
            )
        }
        routingManager.projectionExtra = extra
        routingManager.projectionArrivalMargin = travelMode.tuning.arrivalRadius + 1
    }

    // MARK: - Compass health

    /// True while the phone's compass disagrees with the direction of travel (see `CompassHealth`):
    /// the dial shows a ghost compass at the GPS direction and offers "Recalibrate".
    @Published private(set) var compassSuspect = false
    /// The GPS direction of travel the ghost compass is drawn at (degrees clockwise from north).
    @Published private(set) var compassPredicted: Double?
    /// True for a few seconds after the user taps "Recalibrate" (shows the figure-8 hint).
    @Published private(set) var recalibratingCompass = false
    /// True while the dial is steered by GPS direction instead of the (suspect) compass: the compass
    /// still tracks the phone turning, so its reading is shifted by the offset between it and the GPS
    /// course, re-measured whenever the traveller is moving steadily. Ends by itself once the compass
    /// agrees with the direction of travel again, or when the user taps "Undo".
    @Published private(set) var usingGPSHeading = false
    private var headingCorrection: Double = 0
    private var compassHealth = CompassHealth()

    func useGPSDirection() {
        guard compassSuspect else { return }
        if let predicted = compassHealth.predictedHeading {
            headingCorrection = CompassHealth.signedDifference(predicted, from: locationManager.heading)
        }
        usingGPSHeading = true
    }

    func stopUsingGPSDirection() { usingGPSHeading = false }

    private func updateCompassHealth() {
        guard Perf.on("compasshealth") else { return }
        if Perf.ghost {
            if !compassSuspect { compassSuspect = true; compassPredicted = 40 }
            return
        }
        guard locationManager.hasReliableHeading, let fix = locationManager.location else { return }
        let now = Date()
        let fresh = now.timeIntervalSince(fix.timestamp) < 6 && (fix.courseAccuracy < 0 || fix.courseAccuracy <= 25)
        compassHealth.observe(course: fresh ? fix.course : -1, speed: fresh ? fix.speed : 0, at: now)
        compassHealth.evaluate(heading: locationManager.heading, headingAccuracy: locationManager.headingAccuracy, at: now)
        let suspect = compassHealth.status == .suspect
        let predicted = suspect ? compassHealth.predictedHeading : nil
        if suspect != compassSuspect { compassSuspect = suspect }
        if predicted != compassPredicted { compassPredicted = predicted }
        if usingGPSHeading {
            if !suspect {
                usingGPSHeading = false          // the compass has proved itself again
            } else if let course = compassHealth.steadyCourse(at: now) {
                let fresh = CompassHealth.signedDifference(course, from: locationManager.heading)
                if abs(CompassHealth.signedDifference(fresh, from: headingCorrection)) > 2 {
                    headingCorrection = fresh
                    objectWillChange.send()
                }
            }
        }
    }

    /// iOS can't be told to recalibrate the magnetometer, so this restarts the heading service (clearing
    /// stuck sensor-fusion state, and letting iOS raise its own figure-8 prompt if it wants), keeps the
    /// warning up until the compass has agreed with the direction of travel twice, and asks the user to
    /// wave the phone in a figure-8 meanwhile.
    func recalibrateCompass() {
        guard !recalibratingCompass else { return }
        locationManager.restartHeading()
        compassHealth.noteRecalibrating(at: Date())
        recalibratingCompass = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.recalibratingCompass = false
        }
    }

    // MARK: - Audio cues

    private var audioFired = Set<Int>()
    private var audioCardID: Int?

    /// Plays the tone / spoken cue when the traveller crosses one of the mode's announcement points
    /// (driving 100/50/15 m, cycling 50/15 m, walking and running 15 m) before the next turn or the
    /// destination. Each point fires once per instruction; a GPS jump past two of them plays only the
    /// nearest. Does nothing when audio guidance is off.
    private func announceIfDue() {
        guard audioStyle != .off, let card = upcomingCard else { audioCardID = nil; return }
        if audioCardID != card.id {
            audioCardID = card.id
            audioFired = []
        }
        guard let point = AudioCuePlan(mode: travelMode).crossedPoint(currentDistance: distanceToManeuver, fired: &audioFired) else { return }
        switch audioStyle {
        case .tone:
            audioManager.playTones(count: AudioCuePlan.toneCount(forDistance: point), pan: AudioPan(turn: card.turn.dir))
        case .voice:
            audioManager.speak(VoiceScript().cue(for: card, distanceMetres: Double(point), imperial: opts.units == "Miles"))
        case .off:
            break
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
        routingManager.updateProgress(userLocation: currentPosition, activity: travelMode)
        checkArrival()
        bakeRouteLineIfNeeded()
        // Skips a pointless reroute fetch for a route that's about to be torn down anyway.
        guard !arrived else { return }
        rerouteIfOffRoute()
    }


    /// Once within the mode's arrival radius of the actual destination: stop polling, drop the now-
    /// pointless baked guidance data, and show the completion screen — there's nothing left
    /// for guidance to compute once the trip is over.
    private var lastArrivalCheckPosition: CLLocationCoordinate2D?

    func checkArrival() {
        guard guiding, !arrived, let destinationCoordinate else { return }
        defer { lastArrivalCheckPosition = currentPosition }
        // Checked on the path travelled since the last check, not just where the traveller is
        // now — at 40 km/h a 5m circle is easily stepped over between two one-second checks.
        var reached = CompassManager.distance(from: currentPosition, to: destinationCoordinate) <= travelMode.tuning.arrivalRadius
        if !reached, let previous = lastArrivalCheckPosition,
           CompassManager.distance(from: previous, to: currentPosition) < 200,
           let closest = CompassManager.nearestPoint(on: [previous, currentPosition], to: destinationCoordinate) {
            reached = closest.distance <= travelMode.tuning.arrivalRadius
        }
        guard reached else { return }
        print("[AppModel] Arrived at destination")
        cardsExpanded = false
        arrived = true
        audioManager.finishGuidance()
        routeDataGenerator.clearGuidanceData()
        locationCheckScheduler.stop()
        routingManager.cancelFetch()
        RoutePersistence.clear()
    }

    /// If the traveller has drifted off the planned route (a wrong turn, or a real GPS fix
    /// that's left the road), fetch a fresh route from wherever they actually are now, rather
    /// than leaving them staring at a line that no longer matches where they're going. Guarded
    /// only on `isLoading` (no piling up while a fetch is in flight) — the reroute cooldown/cap
    /// and all retry behaviour now live in `RoutingGovernor`, so a persistent off-route reading
    /// can't hammer the routing API; it just gets told "not yet" until the cooldown clears.
    private func rerouteIfOffRoute() {
        guard routingManager.isOffRoute, !routingManager.isLoading, let destinationCoordinate else { return }
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
    /// fixed fallback placeholder. Everything that needs "where am I" should read this, not
    /// `fallbackPosition` directly.
    var currentPosition: CLLocationCoordinate2D { locationManager.coordinate ?? fallbackPosition }
    var hasRealLocation: Bool { locationManager.coordinate != nil }

    /// The simulator with no location set has no fix by design; the fixed placeholder stands in so
    /// development still works. A real phone never guesses where you are — see `fetchRouteAndWait`.
    private static let usesFallbackOrigin: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// Something about location access that stops guidance working, for the compass screen to explain.
    enum LocationIssue { case denied, reducedAccuracy, searching }
    var locationIssue: LocationIssue? {
        switch locationManager.authorizationStatus {
        case .denied, .restricted: return .denied
        case .notDetermined: return nil
        default: break
        }
        if locationManager.isReducedAccuracy { return .reducedAccuracy }
        if guiding, !arrived, !hasRealLocation, !Self.usesFallbackOrigin { return .searching }
        return nil
    }
    /// The device's real compass heading once it's reliable, else 0 (screen-up as a
    /// stand-in "north") — matches the old fixed behaviour until a real heading arrives.
    var currentHeading: CLLocationDirection {
        guard locationManager.hasReliableHeading else { return 0 }
        guard usingGPSHeading else { return locationManager.heading }
        return (locationManager.heading + headingCorrection + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Idle: not guiding, and no place selected to point at. The dial goes
    /// north-up and flat, with the cardinal markers emphasized, so it's unmistakably at rest.
    var isIdle: Bool { !guiding && destKind == .none }
    /// A subtle idle-only needle wobble — cosmetic "alive" motion, not a stand-in for any
    /// real position, speed, or direction reading.
    /// Half-amplitude (degrees) of the needle's gentle sway: a little more when just pointing,
    /// less while guiding, none when idle or arrived. The sway itself is animated inside the dial.
    var swayAmplitude: Double { isIdle || arrived ? 0 : (guiding ? 1.35 : 2.7) }

    /// True once a real OSRM route has been fetched for the current destination — driving
    /// the turn card and needle with actual turn-by-turn data instead of a straight line.
    var hasRealRoute: Bool { routingManager.hasRoute }

    /// The instruction the traveller is heading for right now (nil before a route loads).
    var upcomingCard: GuidanceCard? { hasRealRoute ? routingManager.upcomingCard : nil }

    /// Metres along the road to that instruction's action point.
    var distanceToManeuver: Double { routingManager.distanceToUpcoming }

    /// Real distance to whatever's currently relevant: the next instruction while a route is
    /// loaded and guiding, otherwise a straight line to the destination. Zero when there's
    /// nothing selected — never a simulated countdown.
    var activeDist: Double {
        if guiding, hasRealRoute, !arrived { return distanceToManeuver }
        if let destinationCoordinate { return CompassManager.distance(from: currentPosition, to: destinationCoordinate) }
        return 0
    }

    var far: Double {
        if guiding, hasRealRoute { return routingManager.legFraction }
        return max(0, min(1, activeDist / (guiding ? travelMode.tuning.polylineRevealDistance : 1200)))
    }

    /// The turn card's headline: the *upcoming* instruction (never the manoeuvre already made),
    /// otherwise a loading/error message, or a plain "head toward X" while the route is still
    /// being fetched.
    var turnCopy: String {
        if routingManager.isLoading { return "Finding your route…" }
        if guiding, hasRealRoute { return upcomingCard?.title ?? "You've arrived" }
        return dest.isEmpty ? "Head toward your destination" : "Head toward \(dest)"
    }

    /// The routing profile for the selected mode (walk and run both use walking).
    var travelProfile: TravelProfile {
        travelMode.profile
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
        return upcomingCard?.turn.dir ?? .straight
    }

    /// Whether the real route line is drawn. It only comes in for the last 500m, to pinpoint the
    /// destination and how to reach it — before that, the compass and the cards do the guiding.
    var showsPolyline: Bool {
        guiding && !arrived && hasRealRoute && routingManager.remainingDistance <= travelMode.tuning.polylineRevealDistance
    }

    /// Whether the full-screen card list is pulled up.
    @Published var cardsExpanded = false

    /// The line under the current card's headline, by how far off the turn is: a long way (stay on
    /// this road), coming up, the final approach, then "Now".
    var currentPhaseText: String {
        guard guiding, let card = upcomingCard else { return "" }
        let d = distanceToManeuver
        if card.kind == .arrive { return d > 30 ? "Almost there" : "Here" }
        if d > travelMode.tuning.farCutoff { return "Continue" }
        if d > 100 { return "Coming up" }
        if d > 30 { return "Get ready" }
        return "Now"
    }

    /// "Get ready" and "Now" — the last 100m before a turn — are the only phase lines that
    /// get picked out in the accent colour; everything earlier is quiet secondary text.
    var currentPhaseHighlighted: Bool {
        guard guiding, let card = upcomingCard, card.kind != .arrive else { return false }
        return distanceToManeuver <= 100
    }

    /// The next real turn (its shape and how far off it is) — nil on a straight run, with no
    /// route, or at arrival. Roundabouts report their *exit*, not the entry.
    var upcomingTurn: (turn: TurnShape, distance: Double)? {
        guard guiding, let card = upcomingCard, card.kind != .arrive, card.kind != .depart,
              card.turn.side != .straight else { return nil }
        return (card.turn, distanceToManeuver)
    }

    /// How early the compass starts showing an arrow for an upcoming turn — 300m standing still,
    /// stretching to 1km at 100 km/h, since faster travel needs earlier warning.
    private var arrowRange: Double { 300 + min(1, speedKmh / 100) * 700 }

    /// The arrow beside the distance readout: straight up by default, then a bend in the
    /// upcoming turn's direction, or a U-turn arrow for sharp turns and U-turns.
    var dialArrowSymbol: String {
        guard !arrived, let upcoming = upcomingTurn, upcoming.distance <= arrowRange else { return "arrow.up" }
        let side = upcoming.turn.side == .left ? "left" : "right"
        switch upcoming.turn.severity {
        case .uTurn, .sharp: return "arrow.uturn.\(side)"
        case .slight: return "arrow.up.\(side)"
        case .normal: return "arrow.turn.up.\(side)"
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
        if guiding, hasRealRoute, !arrived {
            // Aimed at where the instruction actually happens — for a roundabout that's the EXIT
            // (so the needle says left, straight or right, never a hard turn into the circle) —
            // and at the destination itself once the last instruction is behind us.
            let target = upcomingCard?.kind == .arrive ? destinationCoordinate : (upcomingCard?.exitCoordinate ?? destinationCoordinate)
            if let target {
                let bearing = CompassManager.bearing(from: routingManager.projectedPosition(from: currentPosition), to: target)
                return CompassManager.relativeBearing(heading: currentHeading, bearing: bearing)
            }
        }
        if let destinationCoordinate {
            let bearing = CompassManager.bearing(from: currentPosition, to: destinationCoordinate)
            return CompassManager.relativeBearing(heading: currentHeading, bearing: bearing) 
        }
        return 0
    }

    // MARK: - Compass tilt (see CompassTilt.swift for the algorithm)

    /// Angles for the user's "Compass tilt" setting (Off / Slight / Hard).
    var tiltAngles: CompassTilt.Angles { .forSetting(opts.tilt) }

    /// Held within a leg so GPS jitter can't flicker the dial back to a bigger tilt: both stages
    /// only ever advance (toward "none" / toward "strong") until the next instruction card.
    @Published private(set) var frontStep = 0
    @Published private(set) var sideStage: CompassTilt.SideStage = .none
    private var tiltLegKey: String?

    /// Recomputes the held tilt stages. Called about once a second and whenever guidance state changes.
    func updateTiltStages() {
        // Every @Published write redraws the whole compass screen, even when the value is unchanged,
        // so each assignment below is guarded. (Measured: this alone was ~2 redraws/s for nothing.)
        guard guiding, !arrived, hasRealRoute, let card = upcomingCard else {
            tiltLegKey = nil
            if frontStep != 0 { frontStep = 0 }
            if sideStage != .none { sideStage = .none }
            return
        }
        let key = "\(card.id)-\(Int(card.legLength))"
        let step = CompassTilt.frontStep(legFraction: routingManager.legFraction)
        let stage = CompassTilt.sideStage(distance: distanceToManeuver)
        let newFront: Int, newSide: CompassTilt.SideStage
        if key != tiltLegKey {
            tiltLegKey = key
            newFront = step
            newSide = stage
        } else {
            newFront = max(frontStep, step)
            newSide = max(sideStage, stage)
        }
        if newFront != frontStep { frontStep = newFront }
        if newSide != sideStage { sideStage = newSide }
    }

    /// Forward/back tilt in degrees. Guidance: max just after a turn, easing to none by the next
    /// one. Point mode: eases with straight-line distance. Flat when idle or arrived.
    var tiltDeg: Double {
        if isIdle || arrived { return 0 }
        if guiding && hasRealRoute { return CompassTilt.frontAngle(step: frontStep, angles: tiltAngles) }
        // Point mode has no legs, only a straight line: same five steps by distance, but gentler.
        return CompassTilt.frontAngle(step: CompassTilt.frontStep(legFraction: far), angles: tiltAngles) * 0.6
    }

    /// Sideways lean toward the upcoming turn (negative = left). None for straight/roundabout-
    /// straight/arrive, none until 500m out, mild to 200m, strong inside 200m.
    var laneDeg: Double {
        guard guiding, !arrived, hasRealRoute else { return 0 }
        return CompassTilt.sideAngle(stage: sideStage, side: upcomingTurn?.turn.side, angles: tiltAngles)
    }

    /// How far the dial's leaning-side edge sits from the centre (as a multiple of its radius) at
    /// `degrees` of lean: 1 + 0.16 × degrees/40. DialView slides the dial so its edge lands here, and
    /// the guide lines are drawn at exactly the mild and strong angles — so they always agree.
    static func leanEdgeFactor(atDegrees degrees: Double) -> Double { 1 + 0.16 * abs(degrees) / 40 }

    /// Real speed over ground from CoreLocation, in km/h — zero whenever there's no real
    /// GPS fix, never a simulated number.
    var speedKmh: Double { max(0, locationManager.speed) * 3.6 }
    /// `speedKmh` converted to the unit the user picked in Settings.
    var displaySpeed: Double { opts.units == "Miles" ? speedKmh * 0.621371 : speedKmh }
    /// Standing still (or GPS noise on a stationary phone). Display-only: it tints the carousel's
    /// active tile white and never changes `travelMode`, which is always the user's own choice.
    var isStationary: Bool { speedKmh <= 2 }

    /// The route line's colour follows the selected mode: on-foot green for walk/run/cycle,
    /// drive blue for driving.
    var routeColor: Color {
        travelMode.isOnFoot ? Color(hex: "2FCF9B") : Color(hex: "3B82F6")
    }

    // MARK: - Audio guidance setting (stored only — not wired to any playback yet)

    let audioManager = AudioManager()
    @Published var audioStyle: AudioGuidanceStyle = AppModel.loadAudioStyle() {
        didSet {
            UserDefaults.standard.set(audioStyle.rawValue, forKey: Self.audioStyleKey)
            audioManager.style = audioStyle
        }
    }
    private static let audioStyleKey = "audioStyle.v1"
    private static func loadAudioStyle() -> AudioGuidanceStyle {
        UserDefaults.standard.string(forKey: audioStyleKey).flatMap(AudioGuidanceStyle.init(rawValue:)) ?? .tone
    }

    // MARK: - Travel mode (manual, authoritative)

    @Published var travelMode: TravelMode = AppModel.loadTravelMode() {
        didSet {
            guard oldValue != travelMode else { return }
            AppModel.saveTravelMode(travelMode)
            updateBackgroundTracking()
            scheduleModeChangeReroute()
        }
    }
    /// Set while a mode-change fetch is in flight, so the UI can say "Switching to X route".
    @Published private(set) var pendingTravelMode: TravelMode?
    private var modeChangeDebounceTask: Task<Void, Never>?
    /// How long the selection must stay put before a mode change reroutes. Settable for tests.
    var modeChangeDebounce: Duration = .milliseconds(600)

    private static let travelModeKey = "travelMode.v1"
    private static func loadTravelMode() -> TravelMode {
        UserDefaults.standard.string(forKey: travelModeKey).flatMap(TravelMode.init(rawValue:)) ?? .walk
    }
    private static func saveTravelMode(_ mode: TravelMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: travelModeKey)
    }

    /// Rapid carousel scrolling restarts the 0.6s timer, so only the settled mode reroutes.
    /// Uses the initial-request path (retries + diagnosis, no reroute cooldown). In Point mode
    /// a change only stores the selection.
    private func scheduleModeChangeReroute() {
        modeChangeDebounceTask?.cancel()
        guard guiding, !arrived, let destinationCoordinate else { return }
        let mode = travelMode
        modeChangeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.modeChangeDebounce ?? .milliseconds(600))
            guard let self, !Task.isCancelled, self.travelMode == mode, self.guiding, !self.arrived else { return }
            self.pendingTravelMode = mode
            await self.fetchRouteAndWait(to: destinationCoordinate, isReroute: false)
            if self.pendingTravelMode == mode { self.pendingTravelMode = nil }
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

    /// Guidance needs somewhere to guide to: without a selected destination there's no route to
    /// fetch, and it would just sit buffering (and burning power) for nothing.
    var canStartGuidance: Bool { destKind != .none && destinationCoordinate != nil }

    func flipMode() {
        if mode == .point {
            guard canStartGuidance else { return }
            startGuidance()
        } else {
            endGuidance()
        }
    }

    /// Fetches (or clears) the real OSRM route for `destination` from wherever the user
    /// actually is right now. Drives the way cards, the compass and the route-preview line on the
    /// Map tab, so a route appears as soon as a destination exists. The on-screen route line is
    /// *not* baked here — see `bakeRouteLineIfNeeded()`.
    private func fetchRoute(to destination: CLLocationCoordinate2D?, isReroute: Bool = false) {
        guard destination != nil else { routingManager.clear(); return }
        Task { await fetchRouteAndWait(to: destination, isReroute: isReroute) }
    }

    /// Awaitable core of `fetchRoute`. Also what a mode change uses (with `isReroute: false`, so
    /// the retry/diagnosis path applies and the reroute cooldown doesn't): the old route stays
    /// until the new one lands, then cards, polyline and the persisted trip swap together.
    private func fetchRouteAndWait(to destination: CLLocationCoordinate2D?, isReroute: Bool) async {
        guard let destination else { routingManager.clear(); return }
        // Never route from a guessed position: until the first real fix arrives, wait for it (the
        // compass screen says "Finding your location…") rather than start from the placeholder.
        if !hasRealLocation, !Self.usesFallbackOrigin {
            objectWillChange.send()
            while !hasRealLocation {
                try? await Task.sleep(for: .milliseconds(500))
                // Gave up waiting, or the destination changed / guidance ended meanwhile.
                guard guiding, !arrived, destinationCoordinate?.latitude == destination.latitude,
                      destinationCoordinate?.longitude == destination.longitude else { return }
            }
        }
        let origin = currentPosition
        let profile = travelProfile
        await routingManager.getRoute(from: origin, to: destination, profile: profile, isReroute: isReroute)
        guard guiding, routingManager.hasRoute, !arrived else { return }
        if let route = routingManager.currentRoute {
            if Perf.on("persist") { RoutePersistence.save(PersistedTrip(route: route, destinationCoordinate: destination, destinationName: dest, profile: profile)) }
        }
        // The old route line describes a road that's no longer the plan (reroute or mode
        // switch) — drop it; it's baked fresh from the new route when it's actually needed.
        // Harmless on the very first fetch, where nothing is baked yet.
        routeDataGenerator.clearGuidanceData()
        // `start` is idempotent. Guarded on `!arrived` above so a fetch that outlived an
        // arrival can't silently restart the scheduler.
        startLocationChecks()
    }

    /// The route line is only ever drawn for the last 500m, so it's only ever *computed* then: the
    /// moment the traveller comes within 500m of the destination this bakes just that final stretch
    /// (the rest of the route is never turned into line geometry at all). Cheap to call every tick —
    /// it does nothing unless the line is due and not already there.
    func bakeRouteLineIfNeeded() {
        guard !arrived, showsPolyline, routeDataGenerator.guidanceData == nil, !routeDataGenerator.isGenerating else { return }
        let ahead = routingManager.remainingPolyline
        guard ahead.count > 1 else { return }
        let progress = routingManager.progressAlong
        let remainingSteps = routingManager.steps.filter { $0.endAlong > progress }
        print("[AppModel] Within 500m of the destination — baking the route line (\(Int(routingManager.remainingDistance))m)")
        routeDataGenerator.generateGuidanceData(polyline: ahead, steps: remainingSteps, mode: travelMode)
    }

    /// Starts (or resumes) `locationCheckScheduler` for the current mode/activity, and runs
    /// one check immediately rather than waiting out a full interval before the guidance
    /// line has anything real to show.
    private func startLocationChecks() {
        guard Perf.on("sched") else { return }
        locationCheckScheduler.start(
            mode: mode,
            activityProvider: { [weak self] in self?.travelMode ?? .walk },
            onCheck: { [weak self] in self?.performLocationCheck() }
        )
    }

    func startGuidance() {
        guard canStartGuidance else { return }
        etaManager.reset()
        lastArrivalCheckPosition = nil
        mode = .guidance
        arrived = false
        fetchRoute(to: destinationCoordinate)
        startLocationChecks()
        performLocationCheck()
    }

    func endGuidance() {
        audioManager.stop()
        cardsExpanded = false
        etaManager.reset()
        mode = .point
        arrived = false
        routeDataGenerator.clearGuidanceData()
        locationCheckScheduler.stop()
        // A routing failure never stops guidance on its own (see RoutingGovernor) — this is
        // the one place that does, so it's also the one place that should cancel any retry
        // loop still running in the background.
        routingManager.cancelFetch()
        RoutePersistence.clear()
        // The route itself stays put — the destination is still selected, so the Map tab
        // keeps showing the preview line until the user picks something new or clears it.
    }

    /// Restores a trip left mid-flight when the app was last closed — skips the network
    /// entirely, straight from the saved `Route`. Called once at launch.
    private func restorePersistedTrip() {
        guard let trip = RoutePersistence.load() else { return }
        destinationCoordinate = trip.destinationCoordinate
        dest = trip.destinationName
        destKind = .place
        mode = .guidance
        routingManager.restore(route: trip.route, destination: trip.destinationCoordinate, profile: trip.profile)
        startLocationChecks()
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
            // Guidance is refused until there's a coordinate — start it now if that's the default.
            if self.defaultNavMode == .guidance, self.mode != .guidance { self.startGuidance(); return }
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
        let placemark = mapItem.placemark
        let address = [placemark.thoroughfare, placemark.locality].compactMap { $0 }.joined(separator: ", ")
        remember(name: name, coordinate: placemark.coordinate, subtitle: address.isEmpty ? nil : address)

        destinationCoordinate = placemark.coordinate
        beginNavigatingToDestination()
    }

    /// Picks a past destination using the coordinate it was saved with — no geocoding
    /// round-trip, so it can't fail or resolve to a different place.
    func pickRecent(_ place: RecentPlace) {
        dest = place.name
        destKind = .place
        searchOpen = false
        searchQuery = ""
        remember(name: place.name, coordinate: place.coordinate, subtitle: place.subtitle)
        destinationCoordinate = place.coordinate
        beginNavigatingToDestination()
    }

    private func remember(name: String, coordinate: CLLocationCoordinate2D, subtitle: String? = nil) {
        var updated = recentSearches
        // Same name *and* place counts as the same entry; two branches of the same shop don't merge.
        updated.removeAll { $0.name == name && CompassManager.distance(from: $0.coordinate, to: coordinate) < 150 }
        updated.insert(RecentPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, subtitle: subtitle), at: 0)
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
