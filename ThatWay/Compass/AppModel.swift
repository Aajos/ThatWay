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
    @Published var storeTab: StoreTab = .themes
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
    @Published var dest = "Sunrise Bakery"
    @Published var destKind: DestKind = .place
    @Published var destColor: Color?
    @Published var destInitials = ""
    @Published var recentSearches = ["Sunrise Bakery", "Home", "Baker Street Lot", "The Office", "Riya's place"]

    // Real routing (OSRM) and real location (CoreLocation via LocationManager). Friends
    // stay on the simulated system below. `simulatedPosition` is now only a fallback
    // walker — used in place of a real GPS fix when running in the Simulator without a
    // simulated location, or before permission is granted — everything that needs "where
    // the user is" should read `currentPosition`, which prefers the real fix.
    @Published var destinationCoordinate: CLLocationCoordinate2D? = AppModel.mockDestinations["Sunrise Bakery"]
    @Published var simulatedPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    let routingManager = RoutingManager()
    let locationManager = LocationManager()

    static let mockUserLocation = CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153) // Circular Quay
    static let mockDestinations: [String: CLLocationCoordinate2D] = [
        "Sunrise Bakery": CLLocationCoordinate2D(latitude: -33.8587, longitude: 151.2140),  // near the Opera House
        "Home": CLLocationCoordinate2D(latitude: -33.8908, longitude: 151.2743),            // Bondi Beach
        "Baker Street Lot": CLLocationCoordinate2D(latitude: -33.8737, longitude: 151.1998), // Darling Harbour
        "The Office": CLLocationCoordinate2D(latitude: -33.8523, longitude: 151.2108),       // Circular Quay
        "Riya's place": CLLocationCoordinate2D(latitude: -33.8600, longitude: 151.2200),     // Woolloomooloo
        "Barangaroo": CLLocationCoordinate2D(latitude: -33.8599, longitude: 151.2008),       // test destination
    ]

    // Idle ambient animation tick — purely cosmetic (drives `sway`, a subtle needle
    // wobble at rest); never used to fake a position, speed, or distance reading.
    @Published var t = 0

    // Profile
    @Published var vis: Visibility = .friends
    @Published var closeKm: Double = 8

    // Accessibility — added to every Nunito font size app-wide (see NunitoFont.swift).
    @Published var extraTextSize: Double = 0 {
        didSet { Nunito.extraSize = extraTextSize }
    }

    // Floating mode toggle
    @Published var togX: CGFloat = 244
    @Published var togY: CGFloat = 84
    @Published var dragging = false

    @Published var opts = NavOptions()

    private var timer: AnyCancellable?

    let tiltStrength: Double = 0.7
    static let togW: CGFloat = 132
    static let togH: CGFloat = 62
    static let exclusionRadius: CGFloat = 140
    static let cardExclusionRadius: CGFloat = 60

    init() {
        timer = Timer.publish(every: 0.09, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        locationManager.requestPermission()
        // The default demo destination is set directly above rather than through
        // `pickPlace`, so it needs its own kick to fetch a preview route on launch.
        fetchRoute(to: destinationCoordinate)
    }

    func tick() {
        t += 1
        if guiding, routingManager.hasRoute {
            advanceSimulatedPosition()
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

    /// Advances guidance progress each tick. With a real GPS fix, the phone's own motion
    /// is authoritative — this just re-checks the real position against the route. Without
    /// one (Simulator with no simulated location, or permission not yet granted), it falls
    /// back to walking a traveller along the route's real geometry at a fixed pace, purely
    /// so there's real geometry to look at while developing without a device.
    private func advanceSimulatedPosition() {
        guard !hasRealLocation else {
            routingManager.updateProgress(userLocation: currentPosition)
            rerouteIfOffRoute()
            return
        }
        let polyline = routingManager.routePolyline
        guard !polyline.isEmpty else { return }
        let tickInterval = 0.09
        routeProgressMeters += Self.fallbackWalkSpeed * tickInterval
        if let point = CompassManager.pointAlong(polyline, distance: routeProgressMeters) {
            simulatedPosition = point
        }
        routingManager.updateProgress(userLocation: simulatedPosition)
        rerouteIfOffRoute()
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
        fetchRoute(to: destinationCoordinate)
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

    /// Idle: not guiding, and no place or friend selected to point at. The dial goes
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

    var needleDeg: Double {
        // Idle: no destination at all — rest dead on north rather than the ambient sway.
        if isIdle { return 0 }
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

    var dialScale: Double { guiding ? CompassGeometry.scaleGuide : CompassGeometry.scalePoint }
    /// Fully flat at rest in idle mode — no lean at all, so the dial visibly settles.
    var tiltDeg: Double { isIdle ? 0 : far * 54 * tiltStrength }
    var laneDeg: Double {
        guard guiding, hasRealRoute else { return 0 }
        switch turnDir {
        case .left: return -10
        case .right: return 10
        case .straight: return 0
        }
    }

    /// Real speed over ground from CoreLocation, in km/h — zero whenever there's no real
    /// GPS fix, never a simulated number.
    var speedKmh: Double { max(0, locationManager.speed) * 3.6 }
    /// `speedKmh` converted to the unit the user picked in Settings.
    var displaySpeed: Double { opts.units == "Miles" ? speedKmh * 0.621371 : speedKmh }
    var auto: String { speedKmh < 7 ? "WALKING" : speedKmh < 15 ? "RUNNING" : "DRIVING" }
    var activity: String { opts.activity == "Automatic" ? auto : opts.activity.uppercased() }
    var routeColor: Color { activity == "DRIVING" ? Color(hex: "3B82F6") : Color(hex: "2FCF9B") }

    var friendMode: Bool { destKind == .friend && destColor != nil }
    var accent: Color { friendMode ? (destColor ?? currentTheme.accent) : currentTheme.accent }

    /// The 2-3 tones the dial's glass rim gradient pulls from — the selected friend's
    /// colors when pointing at one, otherwise the theme's own accent pairing.
    var dialGlassColors: [Color] {
        friendMode ? (destColor ?? currentTheme.accent).dominantTrio
            : [currentTheme.accent, Color(hex: "34D6A5"), currentTheme.accent.hueShifted(24)]
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
    /// not just once guidance formally starts.
    private func fetchRoute(to destination: CLLocationCoordinate2D?) {
        guard let destination else { routingManager.clear(); return }
        let origin = currentPosition
        Task { await routingManager.getRoute(from: origin, to: destination) }
    }

    func startGuidance() {
        mode = .guidance
        routeProgressMeters = 0
        lastRerouteAt = nil
        simulatedPosition = Self.mockUserLocation
        fetchRoute(to: destinationCoordinate)
    }

    func endGuidance() {
        mode = .point
        routeProgressMeters = 0
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

    /// A friend's real, locatable coordinate, derived from the user's current position —
    /// see `Friend.coordinate(near:)`. Used for both the compass needle/routing and the
    /// Map tab's annotation, so a friend behaves exactly like any other real destination.
    func coordinate(for f: Friend) -> CLLocationCoordinate2D { f.coordinate(near: currentPosition) }

    func goToFriend(_ f: Friend) {
        dest = f.name
        destKind = .friend
        destColor = f.color
        destInitials = f.initials
        mode = .point
        let coordinate = coordinate(for: f)
        destinationCoordinate = coordinate
        fetchRoute(to: coordinate)
    }

    /// Drops whatever place or friend is selected and returns the compass to idle:
    /// north-up, flat, cardinal markers emphasized.
    func clearDestination() {
        destKind = .none
        dest = ""
        destColor = nil
        destInitials = ""
        destinationCoordinate = nil
        routingManager.clear()
    }

    func pickPlace(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dest = trimmed
        destKind = .place
        destColor = nil
        destInitials = ""
        searchOpen = false
        searchQuery = ""
        mode = .point
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 5 { recentSearches.removeLast() }

        // Show the mock coordinate immediately if this name happens to be one of the test
        // destinations (instant feedback, no network round-trip needed), then replace it
        // with a real geocoded result once that resolves. Falls back to staying on the
        // mock value (or nil, if there wasn't one) if the real search fails or is offline.
        destinationCoordinate = Self.mockDestinations[trimmed]
        fetchRoute(to: destinationCoordinate)
        let origin = currentPosition
        Task { [weak self] in
            guard let self, let real = await PlaceSearch.firstResult(for: trimmed, near: origin) else { return }
            guard self.dest == trimmed else { return } // a newer search superseded this one
            self.destinationCoordinate = real
            self.fetchRoute(to: real)
        }
    }

    /// Selects a destination straight from a real search result — already has a real
    /// coordinate, so no geocoding round-trip is needed before showing it.
    func pickPlace(mapItem: MKMapItem) {
        let name = mapItem.name ?? "Selected place"
        dest = name
        destKind = .place
        destColor = nil
        destInitials = ""
        searchOpen = false
        searchQuery = ""
        mode = .point
        recentSearches.removeAll { $0 == name }
        recentSearches.insert(name, at: 0)
        if recentSearches.count > 5 { recentSearches.removeLast() }

        let coordinate = mapItem.placemark.coordinate
        destinationCoordinate = coordinate
        fetchRoute(to: coordinate)
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
        destColor = nil
        destInitials = ""
        searchOpen = false
        searchQuery = ""
        destinationCoordinate = prompt.coordinate
        recentSearches.removeAll { $0 == prompt.name }
        recentSearches.insert(prompt.name, at: 0)
        if recentSearches.count > 5 { recentSearches.removeLast() }
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
        storeTab = .donate
    }

    func selectTab(_ s: AppScreen) {
        screen = s
        searchOpen = false
        avatarSheet = false
    }

    /// How much room the floating tab bar needs at the bottom, so the toggle never slides
    /// under it and reads as "vanished."
    static let tabBarClearance: CGFloat = 90

    /// Clamp the floating toggle inside the screen (20px edge padding, and clear of the tab
    /// bar at the bottom). If it strays within 140pt of the compass dial's centre, shove it
    /// sideways clear of the dial; if it strays within 60pt of the destination card, lift it
    /// straight up clear of the card. Both pushes are solved geometrically for the exact
    /// horizontal/vertical distance needed — not just "however far it currently is short by"
    /// — so a toggle sitting directly above or below the target still clears it in one move.
    func placeToggle(_ x: CGFloat, _ y: CGFloat, in size: CGSize, dialCenter: CGPoint, cardFrame: CGRect?) -> CGPoint {
        let edgePadding: CGFloat = 20
        func clamp(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(
                x: max(edgePadding, min(size.width - Self.togW - edgePadding, px)),
                y: max(edgePadding, min(size.height - Self.togH - edgePadding - Self.tabBarClearance, py))
            )
        }
        func pushHorizontally(_ p: CGPoint, awayFrom target: CGPoint, radius: CGFloat) -> CGPoint {
            let center = CGPoint(x: p.x + Self.togW / 2, y: p.y + Self.togH / 2)
            let dy = center.y - target.y
            guard abs(dy) < radius else { return p }
            let requiredDx = (radius * radius - dy * dy).squareRoot() + 1
            let currentDx = center.x - target.x
            guard abs(currentDx) < requiredDx else { return p }
            let direction: CGFloat = currentDx >= 0 ? 1 : -1
            let newCenterX = target.x + direction * requiredDx
            var result = clamp(newCenterX - Self.togW / 2, p.y)

            // A narrow screen can make the ideal horizontal-only escape wider than the
            // screen itself — edge-clamping would then silently drop the toggle back inside
            // the exclusion circle. If that happens, finish clearing it vertically too.
            let resultCenter = CGPoint(x: result.x + Self.togW / 2, y: result.y + Self.togH / 2)
            let resultDist = (pow(resultCenter.x - target.x, 2) + pow(resultCenter.y - target.y, 2)).squareRoot()
            if resultDist < radius {
                let verticalDirection: CGFloat = dy >= 0 ? 1 : -1
                let maxDx = abs(resultCenter.x - target.x)
                let neededDy = (radius * radius - maxDx * maxDx).squareRoot() + 1
                let newCenterY = target.y + verticalDirection * neededDy
                result = clamp(result.x, newCenterY - Self.togH / 2)
            }
            return result
        }
        func pushUp(_ p: CGPoint, awayFrom rect: CGRect, margin: CGFloat) -> CGPoint {
            let center = CGPoint(x: p.x + Self.togW / 2, y: p.y + Self.togH / 2)
            let dx = center.x - min(max(center.x, rect.minX), rect.maxX)
            guard abs(dx) < margin else { return p }
            let requiredDy = (margin * margin - dx * dx).squareRoot() + 1
            let targetY = rect.minY - requiredDy
            guard center.y > targetY else { return p }
            return clamp(p.x, targetY - Self.togH / 2)
        }

        var p = clamp(x, y)
        p = pushHorizontally(p, awayFrom: dialCenter, radius: Self.exclusionRadius)
        if let cardFrame {
            p = pushUp(p, awayFrom: cardFrame, margin: Self.cardExclusionRadius)
        }
        return p
    }
}
