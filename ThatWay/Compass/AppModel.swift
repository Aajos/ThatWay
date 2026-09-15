//
//  AppModel.swift
//  ThatWay
//
//  Simulated navigation state driving the Compass Nav concept screens.
//

import SwiftUI
import Combine
import CoreLocation

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

    // Real routing (OSRM). Friends stay on the simulated system below — only searched
    // places get a real coordinate and a real route — so testing this needs no GPS: the
    // "traveller" is a mock fixed point in Sydney, and guidance mode walks it along the
    // fetched route by interpolating toward each maneuver in turn.
    @Published var destinationCoordinate: CLLocationCoordinate2D? = AppModel.mockDestinations["Sunrise Bakery"]
    @Published var simulatedPosition: CLLocationCoordinate2D = AppModel.mockUserLocation
    let routingManager = RoutingManager()

    static let mockUserLocation = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093) // Sydney CBD
    static let mockDestinations: [String: CLLocationCoordinate2D] = [
        "Sunrise Bakery": CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153),  // near the Opera House
        "Home": CLLocationCoordinate2D(latitude: -33.8908, longitude: 151.2743),            // Bondi Beach
        "Baker Street Lot": CLLocationCoordinate2D(latitude: -33.8737, longitude: 151.1998), // Darling Harbour
        "The Office": CLLocationCoordinate2D(latitude: -33.8523, longitude: 151.2108),       // Circular Quay
        "Riya's place": CLLocationCoordinate2D(latitude: -33.8600, longitude: 151.2200),     // Woolloomooloo
    ]

    // Simulation
    @Published var t = 0
    @Published var dist: Double = 1240
    @Published var stepIdx = 0
    @Published var stepDist: Double = 420
    @Published var speed: Double = 5

    // Profile
    @Published var vis: Visibility = .friends
    @Published var closeKm: Double = 8

    // Floating mode toggle
    @Published var togX: CGFloat = 244
    @Published var togY: CGFloat = 84
    @Published var dragging = false

    // Map
    @Published var mapX: CGFloat = 0
    @Published var mapY: CGFloat = 0
    @Published var mapZoom: CGFloat = 1
    @Published var mapRot: Double = 0
    @Published var mapTilt: Double = 0

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
    }

    func tick() {
        t += 1
        if mode == .point {
            dist -= 7
            if dist < 40 { dist = 1240 }
            speed = 4.6 + sin(Double(t) / 30) * 0.9
        } else {
            if routingManager.hasRoute {
                advanceSimulatedPosition()
            } else {
                stepDist -= 9
                if stepDist <= 10 {
                    stepIdx = (stepIdx + 1) % NavStep.all.count
                    stepDist = NavStep.all[stepIdx].dist
                }
            }
            speed = 52 + sin(Double(t) / 45) * 26
        }
    }

    /// Moves the mock traveller a fraction of the way toward the current maneuver each
    /// tick — an easing walk rather than a fixed speed, so it always makes visible progress
    /// whether the next turn is 50m or 900m away, and settles smoothly as it arrives.
    private func advanceSimulatedPosition() {
        guard let target = routingManager.currentStep?.coordinate else { return }
        let fraction = 0.12
        simulatedPosition = CLLocationCoordinate2D(
            latitude: simulatedPosition.latitude + (target.latitude - simulatedPosition.latitude) * fraction,
            longitude: simulatedPosition.longitude + (target.longitude - simulatedPosition.longitude) * fraction
        )
        routingManager.updateProgress(userLocation: simulatedPosition)
    }

    // MARK: - Derived state

    var currentTheme: AppTheme { AppTheme.byId(theme) }
    var guiding: Bool { mode == .guidance }

    /// Idle: not guiding, and no place or friend selected to point at. The dial goes
    /// north-up and flat, with the cardinal markers emphasized, so it's unmistakably at rest.
    var isIdle: Bool { !guiding && destKind == .none }
    var step: NavStep { NavStep.all[stepIdx] }
    var nextStep: NavStep { NavStep.all[(stepIdx + 1) % NavStep.all.count] }
    var sway: Double { sin(Double(t) / 11) * 9 }

    /// True once a real OSRM route is actively driving guidance mode (as opposed to the
    /// simulated mock turns, which still cover friend-pointing and the no-route fallback).
    var hasRealRoute: Bool { guiding && routingManager.hasRoute }

    /// Straight-line distance from the mock traveller to the current maneuver point.
    var distanceToManeuver: Double {
        guard let coordinate = routingManager.currentStep?.coordinate else { return 0 }
        return CompassManager.distance(from: simulatedPosition, to: coordinate)
    }

    var activeDist: Double {
        if guiding {
            return hasRealRoute ? distanceToManeuver : stepDist
        }
        if let destinationCoordinate {
            return CompassManager.distance(from: simulatedPosition, to: destinationCoordinate)
        }
        return dist
    }

    var far: Double {
        if hasRealRoute, let metres = routingManager.currentStep?.distance {
            return max(0, min(1, distanceToManeuver / max(metres, 1)))
        }
        return max(0, min(1, activeDist / (guiding ? 500 : 1200)))
    }

    /// The turn card's headline: the real OSRM instruction once a route is loaded,
    /// otherwise the simulated mock turn (or an arrival/loading/error message).
    var turnCopy: String {
        if routingManager.isLoading { return "Finding your route…" }
        if let error = routingManager.errorMessage { return error }
        if hasRealRoute { return routingManager.currentStep?.instruction ?? "You've arrived" }
        return step.copy
    }

    var turnSubtitle: String {
        if hasRealRoute { return "\(fmt(distanceToManeuver)) to go" }
        return step.lane
    }

    var turnDir: TurnDir {
        if hasRealRoute { return routingManager.currentStep?.turnDirection ?? .straight }
        return step.dir
    }

    var needleDeg: Double {
        // Idle: no destination at all — rest dead on north rather than the ambient sway.
        if isIdle { return 0 }
        // Point the needle at the real bearing to the next maneuver (guidance) or the
        // destination (point mode) whenever we have real coordinates for either.
        if hasRealRoute, let coordinate = routingManager.currentStep?.coordinate {
            let bearing = CompassManager.bearing(from: simulatedPosition, to: coordinate)
            return CompassManager.relativeBearing(heading: 0, bearing: bearing) + sway * 0.15
        }
        if !guiding, let destinationCoordinate {
            let bearing = CompassManager.bearing(from: simulatedPosition, to: destinationCoordinate)
            return CompassManager.relativeBearing(heading: 0, bearing: bearing) + sway * 0.3
        }

        let p = 1 - far
        let sTurn: Double = step.dir == .left ? -1 : step.dir == .right ? 1 : 0
        let anticipate = p * p * (3 - 2 * p)
        let throughTurn = max(0, min(1, (p - 0.86) / 0.14))
        let threadRot = -sTurn * 58 * throughTurn * throughTurn
        return guiding ? sTurn * 58 * anticipate + threadRot + sway * 0.22 : sway
    }

    var threadRot: Double {
        let p = 1 - far
        let sTurn: Double = step.dir == .left ? -1 : step.dir == .right ? 1 : 0
        let throughTurn = max(0, min(1, (p - 0.86) / 0.14))
        return -sTurn * 58 * throughTurn * throughTurn
    }

    var dialScale: Double { guiding ? CompassGeometry.scaleGuide : CompassGeometry.scalePoint }
    /// Fully flat at rest in idle mode — no lean at all, so the dial visibly settles.
    var tiltDeg: Double { isIdle ? 0 : far * 54 * tiltStrength }
    var laneDeg: Double {
        if hasRealRoute {
            switch turnDir {
            case .left: return -10
            case .right: return 10
            case .straight: return 0
            }
        }
        return guiding ? CompassGeometry.laneDeg(for: step.side) : 0
    }

    var auto: String { speed < 7 ? "WALKING" : speed < 15 ? "RUNNING" : "DRIVING" }
    var activity: String { opts.activity == "Automatic" ? auto : opts.activity.uppercased() }
    var routeColor: Color { activity == "DRIVING" ? Color(hex: "3B82F6") : Color(hex: "2FCF9B") }
    var routeM: Double {
        (max(50, min(2000, 50 + ((speed - 40) / 80) * 1950)) / 10).rounded() * 10
    }

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

    func startGuidance() {
        mode = .guidance
        stepIdx = 0
        stepDist = NavStep.all[0].dist
        speed = 52
        simulatedPosition = Self.mockUserLocation
        if let destinationCoordinate {
            Task { await routingManager.fetchRoute(from: Self.mockUserLocation, to: destinationCoordinate) }
        } else {
            routingManager.clear()
        }
    }

    func endGuidance() {
        mode = .point
        dist = 1240
        speed = 5
        simulatedPosition = Self.mockUserLocation
        routingManager.clear()
    }

    func setTheme(_ id: ThemeID) {
        let th = AppTheme.byId(id)
        theme = id
        if !th.light { lastDark = id }
    }

    func toggleTheme() {
        setTheme(currentTheme.light ? lastDark : .paper)
    }

    func goToFriend(_ f: Friend) {
        dest = f.name
        destKind = .friend
        destColor = f.color
        destInitials = f.initials
        destinationCoordinate = nil // friends live on the stylised in-app map, not real coordinates
        routingManager.clear()
        mode = .point
        dist = 860
    }

    /// Resets pan/zoom/tilt and spins the map back to north by the shortest path, no
    /// matter how many full turns the rotate buttons have accumulated. `mapRot` is a plain
    /// running total (repeated ±30° taps can push it well past ±360°), and the view's
    /// `.animation(value: mapRot)` always interpolates linearly from the last rendered
    /// value — so snapping straight to 0 would visibly unwind every extra revolution. Instead
    /// this collapses the current angle to its shortest-path equivalent in one unanimated
    /// frame, then animates from THAT to 0 on the next runloop tick.
    func recenterMap() {
        mapX = 0
        mapY = 0
        mapZoom = 1
        mapTilt = 0
        var normalized = mapRot.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized <= -180 { normalized += 360 }
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) { mapRot = normalized }
        DispatchQueue.main.async { [weak self] in self?.mapRot = 0 }
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
        dist = 1240
        destinationCoordinate = Self.mockDestinations[trimmed]
        simulatedPosition = Self.mockUserLocation
        routingManager.clear()
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 5 { recentSearches.removeLast() }
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
