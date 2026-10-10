//
//  WatchModel.swift
//  ThatWayWatch
//
//  Location, heading and route progress for the spike: raw CoreLocation in, `HeadingBlender` and
//  `RouteTracker` (both from ThatWayCore) in the middle, a filtered heading, needle angle and
//  guidance readouts out. The test route is built at runtime relative to where the wearer stands;
//  no coordinate is ever stored or logged.
//

import SwiftUI
import CoreLocation
import ThatWayCore
import ThatWayUI
import WatchKit

@MainActor
final class WatchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum NavMode: String { case point, guidance }
    enum Skin: String, CaseIterable { case needle, wheel, clock }

    /// The same palettes as the iPhone app. Tap the compass to cycle theme, long-press to cycle needle skin.
    @Published var themeID: ThemeID = ThemeID(rawValue: UserDefaults.standard.string(forKey: "watchTheme") ?? "") ?? .ember {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "watchTheme") }
    }
    @Published var skin: Skin = Skin(rawValue: UserDefaults.standard.string(forKey: "watchSkin") ?? "") ?? .needle {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: "watchSkin") }
    }
    var theme: AppTheme { AppTheme.byId(themeID) }

    /// Walk / Run / Cycle only (swipe up/down). Driving is never offered on the watch.
    @Published private(set) var mode: TravelMode = {
        let saved = TravelMode(rawValue: UserDefaults.standard.string(forKey: "watchMode") ?? "") ?? .walk
        return saved.isSafeOnWatch ? saved : .walk
    }()
    /// Set briefly after a mode change so the screen can show its name.
    @Published private(set) var modeFlash: TravelMode?
    /// True once the iPhone says it is in Drive mode: the watch then stops everything and closes.
    @Published private(set) var blockedByDriving = false
    /// Kept in memory for the screen only. Never stored, never logged.
    @Published private(set) var destinationName: String?
    private var routeToken = 0
    private let provider = OSRMRoutingProvider(baseURL: { OSRMHosts.baseURL(for: $0) }, userAgent: "ThatWay-Watch/1.0")
    private var flashTask: Task<Void, Never>?
    func cycleTheme() {
        let all = ThemeID.allCases
        themeID = all[(all.firstIndex(of: themeID)! + 1) % all.count]
        WKInterfaceDevice.current().play(.click)
    }
    func cycleSkin() {
        let all = Skin.allCases
        skin = all[(all.firstIndex(of: skin)! + 1) % all.count]
        WKInterfaceDevice.current().play(.click)
    }

    @Published var navMode: NavMode = .point
    // Blended output
    @Published private(set) var heading: Double?
    @Published private(set) var source: HeadingOutput.Source = .none
    @Published private(set) var needleAngle = ContinuousAngle(0)
    @Published private(set) var ringAngle = ContinuousAngle(0)
    // Raw readings (debug overlay)
    @Published private(set) var speed = 0.0                // m/s, 0 if unknown
    @Published private(set) var course = -1.0
    @Published private(set) var courseAccuracy = -1.0
    @Published private(set) var magnetometer: Double?
    @Published private(set) var magnetometerAccuracy = -1.0
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    // Guidance
    @Published private(set) var progress: RouteTracker.Progress?
    @Published private(set) var hasDestination = false
    /// Straight-line metres to the destination, for Point mode.
    @Published private(set) var straightLineDistance: Double?
    @Published var message = ""

    let manager = CLLocationManager()
    var blender = HeadingBlender()

    // Counters for the session log (reset by the session controller).
    private(set) var locationUpdates = 0
    private(set) var headingUpdates = 0

    private(set) var lastFix: CLLocation?
    private var tracker: RouteTracker?
    private var destination: CLLocationCoordinate2D?       // in memory only
    private var firedStep: Int?
    private var wasOffRoute = false
    private var lastOffRouteHaptic = Date.distantPast
    private var lastSampleLogged = 0.0
    var hapticSet = HapticLibrary.count

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.headingFilter = 1
        authorization = manager.authorizationStatus
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    var batteryPercent: Int {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? -1 : Int((level * 100).rounded())
    }

    func start() {
        guard !blockedByDriving else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func resetCounters() { locationUpdates = 0; headingUpdates = 0 }

    // MARK: Travel mode

    /// Swipe up = next mode, swipe down = previous (walk, run, cycle, wrapping).
    func changeMode(steps: Int) { setMode(mode.onWatch(steps: steps)) }

    private func setMode(_ new: TravelMode) {
        guard new.isSafeOnWatch, new != mode else { return }
        let profileChanged = new.profile != mode.profile
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: "watchMode")
        tracker?.corridor = new.tuning.corridorRadius
        tracker?.arrivalRadius = new.tuning.arrivalRadius
        WKInterfaceDevice.current().play(.click)
        modeFlash = new
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            if !Task.isCancelled { modeFlash = nil }
        }
        SpikeLog.shared.write(["type": "mode", "mode": new.rawValue])
        // Walking and running share one routing profile; cycling needs its own route.
        if profileChanged, destination != nil { Task { await fetchRoute() } }
    }

    /// The iPhone's travel mode arrived. Drive means the watch must not guide.
    func applyPhoneMode(_ phone: TravelMode) {
        if !phone.isSafeOnWatch {
            guard !blockedByDriving else { return }
            blockedByDriving = true
            shutdown()
            WKInterfaceDevice.current().play(.notification)
            SpikeLog.shared.write(["type": "blockedByDriving"])
        } else {
            setMode(phone)
        }
    }

    /// How close the friend the phone is finding is (nil when no Find session is running). The phone does the ranging;
    /// the watch shows it and taps the wrist as the friend gets closer.
    @Published private(set) var proximity: ProximityWatchState?

    func applyProximity(_ new: ProximityWatchState?) {
        let old = proximity
        proximity = new
        guard let new, !blockedByDriving else { return }
        if new.band == .here, old?.band != .here {
            WKInterfaceDevice.current().play(.success)
        } else if let old, new.band < old.band {
            WKInterfaceDevice.current().play(.click)       // one tap per band closer
        }
    }

    /// Stops location, heading and any route: nothing keeps running once the watch has refused to guide.
    func shutdown() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        clearRoute()
    }

    // MARK: Destination (voice search) and real route

    func setDestination(name: String, coordinate: CLLocationCoordinate2D) {
        guard !blockedByDriving else { return }
        destination = coordinate
        destinationName = name
        hasDestination = true
        tracker = nil
        progress = nil
        navMode = .point                    // points straight at it until the route lands
        message = "Finding route…"
        Task { await fetchRoute() }
    }

    private func fetchRoute() async {
        guard let destination else { return }
        guard let fix = lastFix else { message = "Waiting for GPS"; return }
        routeToken += 1
        let token = routeToken
        do {
            let route = try await provider.route(from: fix.coordinate, to: destination, profile: mode.profile)
            guard token == routeToken, !blockedByDriving else { return }
            var t = RouteTracker(route: route, mode: mode)
            progress = t.update(position: fix.coordinate)
            tracker = t
            firedStep = nil
            navMode = .guidance
            message = ""
            WKInterfaceDevice.current().play(.start)
            SpikeLog.shared.write(["type": "route", "metres": Int(route.distance), "steps": route.steps.count, "profile": mode.profile.displayName])
        } catch is CancellationError {
            return
        } catch {
            guard token == routeToken else { return }
            // No route: keep pointing straight at the place rather than leaving the wearer with nothing.
            message = (error as? RoutingError) == .noRoute || (error as? RoutingError) == .noRoadNearby ? "No \(mode.displayName.lowercased()) route" : "No connection: pointing"
            navMode = .point
            progress = nil
            SpikeLog.shared.write(["type": "routeFailed"])
        }
    }

    // MARK: Test route

    /// A route relative to where the wearer is now: 300 m ahead, right turn, 200 m, left turn, 150 m.
    func setTestRoute() {
        guard let fix = lastFix else { message = "Waiting for a GPS fix"; return }
        let route = SyntheticRoute.make(from: fix.coordinate, initialBearing: heading ?? 0,
                                        legs: [.init(metres: 300, turn: .right), .init(metres: 200, turn: .left), .init(metres: 150)])
        tracker = RouteTracker(route: route, mode: mode)
        destination = route.geometry.last
        hasDestination = true
        firedStep = nil
        navMode = .guidance
        message = "Test route set"
        refreshProgress(fix)
    }

    func clearRoute() {
        tracker = nil; destination = nil; destinationName = nil; hasDestination = false; progress = nil; navMode = .point; message = ""
        routeToken += 1
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in
            self.locationUpdates += 1
            self.lastFix = fix
            self.speed = max(0, fix.speed)
            self.course = fix.course
            self.courseAccuracy = fix.courseAccuracy
            // Simulator / screenshot aid: `-spike-autoroute` sets the test route at the first fix.
            if self.tracker == nil, ProcessInfo.processInfo.arguments.contains("-spike-autoroute") { self.setTestRoute() }
            self.refreshProgress(fix)
            self.straightLineDistance = self.destination.map { CompassManager.distance(from: fix.coordinate, to: $0) }
            self.blend()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let accuracy = newHeading.headingAccuracy
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.headingUpdates += 1
            self.magnetometerAccuracy = accuracy
            self.magnetometer = accuracy >= 0 ? value : nil
            self.blend()
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Blending

    private func blend() {
        let fixAge = lastFix.map { Date().timeIntervalSince($0.timestamp) } ?? 99
        let sample = HeadingSample(
            speed: lastFix.map { $0.speed } ?? -1, course: course, courseAccuracy: courseAccuracy, fixAge: fixAge,
            magnetometer: magnetometer, magnetometerAccuracy: magnetometerAccuracy, time: ProcessInfo.processInfo.systemUptime
        )
        let out = blender.update(sample)
        heading = out.heading
        source = out.source
        if let h = out.heading {
            ringAngle.update(to: -h)
            needleAngle.update(to: AngleMath.signedDifference(targetBearing(), from: h))
        }
        logSample(out, sample: sample)
    }

    /// True-north bearing the needle should point at.
    private func targetBearing() -> Double {
        if navMode == .guidance, let progress { return progress.bearingToNext }
        if let fix = lastFix, let destination { return CompassManager.bearing(from: fix.coordinate, to: destination) }
        return 0       // idle: north
    }

    // MARK: Guidance + haptics

    private func refreshProgress(_ fix: CLLocation) {
        guard var t = tracker else { return }
        let p = t.update(position: fix.coordinate)
        tracker = t
        progress = p
        guard navMode == .guidance else { return }
        if p.arrived {
            if firedStep != -1 { firedStep = -1; HapticPlayer.play(hapticSet.pattern(.arrive)); SpikeLog.shared.write(["type": "haptic", "event": "arrive"]) }
        } else if let turn = p.nextTurn, let step = p.nextStepIndex, p.distanceToNext <= 30, firedStep != step {
            firedStep = step
            let event: HapticEvent = turn.side == .left ? .left : .right
            HapticPlayer.play(hapticSet.pattern(event))
            SpikeLog.shared.write(["type": "haptic", "event": event.rawValue])
        }
        if p.offRoute, !wasOffRoute, Date().timeIntervalSince(lastOffRouteHaptic) > 20 {
            lastOffRouteHaptic = Date()
            HapticPlayer.play(hapticSet.pattern(.offRoute))
            SpikeLog.shared.write(["type": "haptic", "event": "offRoute"])
        }
        wasOffRoute = p.offRoute
    }

    // MARK: Logging

    private func logSample(_ out: HeadingOutput, sample: HeadingSample) {
        guard SpikeLog.shared.isOpen else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSampleLogged >= 1 else { return }
        lastSampleLogged = now
        var line: [String: Any] = [
            "type": "heading", "source": out.source.rawValue, "speed": round2(sample.speed), "course": round2(sample.course),
            "courseAcc": round2(sample.courseAccuracy), "mag": sample.magnetometer.map(round2) ?? NSNull(),
            "magAcc": round2(sample.magnetometerAccuracy), "filtered": out.heading.map(round2) ?? NSNull(),
        ]
        // Error against GPS course, only where the course is trustworthy (moving, valid, accurate).
        if sample.speed >= 1.5, sample.course >= 0, sample.courseAccuracy < 0 || sample.courseAccuracy <= 35 {
            if let m = sample.magnetometer { line["errMag"] = round2(AngleMath.signedDifference(m, from: sample.course)) }
            if let h = out.heading { line["errFiltered"] = round2(AngleMath.signedDifference(h, from: sample.course)) }
        }
        SpikeLog.shared.write(line)
    }

    private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
