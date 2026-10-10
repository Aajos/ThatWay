//
//  LocationManager.swift
//  ThatWay
//
//  Wraps CoreLocation to publish the device's live location and compass heading.
//

import CoreLocation
import Combine
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLLocationDirection = 0
    @Published private(set) var headingAccuracy: CLLocationDirection = -1
    @Published private(set) var speed: CLLocationSpeed = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?
    /// True when the user turned off "Precise Location" for the app: fixes are then only good to a
    /// kilometre or so, useless for turn-by-turn. The app asks for temporary full accuracy once per
    /// launch and, if that's declined, shows a card pointing at Settings.
    @Published private(set) var isReducedAccuracy = false
    private var askedForFullAccuracy = false
    /// Running totals for the test log. Plain counters, not @Published: nothing redraws for them.
    private(set) var fixCount = 0
    private(set) var headingCount = 0

    private let manager = CLLocationManager()

    /// True once we've received at least one heading update with a usable accuracy.
    var hasReliableHeading: Bool { headingAccuracy >= 0 }

    var coordinate: CLLocationCoordinate2D? { location?.coordinate }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 1
        // The UI is portrait-only, so the heading is always measured the way the portrait screen faces.
        // (It used to follow the phone's *physical* orientation: glancing at the screen with the phone
        // tipped past upright read as "upside down" and swung the compass 180° / 90°.)
        manager.headingOrientation = .portrait

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            start()
        }
    }

    /// iOS has no separate "compass" permission dialog — heading only ever requires the
    /// same When-In-Use/Always location authorization already requested above, plus the
    /// device actually having a magnetometer (`headingAvailable()`). `requestPermission()`
    /// and `start()` below are what actually turns heading on; there's nothing further to
    /// ask the user for.
    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        default:
            break
        }
    }

    func start() {
        if Perf.on("loc") { manager.startUpdatingLocation() }
        if CLLocationManager.headingAvailable(), Perf.on("heading") {
            manager.startUpdatingHeading()
        }
    }

    /// Keeps location flowing with the screen off, but only while a trip is actually being
    /// guided — otherwise iOS would suspend the app seconds after the screen locks and guidance
    /// would silently stop. Off the rest of the time so Point mode costs nothing in the background.
    private var appliedProfile: LocationProfile?

    /// Applies an accuracy/distance-filter/heading-filter combination, only touching CoreLocation
    /// when something actually changed.
    func apply(_ profile: LocationProfile) {
        guard Perf.on("locprofile"), profile != appliedProfile else { return }
        appliedProfile = profile
        manager.desiredAccuracy = profile.accuracy
        manager.distanceFilter = profile.distanceFilter
        manager.headingFilter = profile.headingFilter
    }

    /// The distance filter currently in force — the most the traveller can move without a new fix.
    var activeDistanceFilter: CLLocationDistance { appliedProfile?.distanceFilter ?? manager.distanceFilter }

    func setBackgroundGuidance(_ on: Bool, activityType: CLActivityType) {
        manager.activityType = activityType
        manager.pausesLocationUpdatesAutomatically = !on
        manager.showsBackgroundLocationIndicator = on
        manager.allowsBackgroundLocationUpdates = on
    }

    /// The compass heading is only needed to draw the dial, so it's switched off whenever the
    /// screen isn't showing it (magnetometer + sensor fusion are not free).
    func setHeadingActive(_ active: Bool) {
        guard CLLocationManager.headingAvailable() else { return }
        if active { manager.startUpdatingHeading() } else { manager.stopUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// iOS offers no way to reset or recalibrate the magnetometer from an app. What an app can do is
    /// tear the heading service down and bring it back up, which discards the sensor-fusion state
    /// that sometimes gets stuck (a flipped or drifting heading), and let iOS raise its own figure-8
    /// calibration prompt if it judges the compass poorly calibrated.
    func restartHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.stopUpdatingHeading()
        manager.dismissHeadingCalibrationDisplay()
        headingAccuracy = -1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.manager.startUpdatingHeading()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        updateAccuracyAuthorization(manager)
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enable it in Settings to use the compass."
        default:
            break
        }
    }

    private func updateAccuracyAuthorization(_ manager: CLLocationManager) {
        let reduced = manager.authorizationStatus != .notDetermined && manager.accuracyAuthorization == .reducedAccuracy
        if reduced != isReducedAccuracy { isReducedAccuracy = reduced }
        guard reduced, !askedForFullAccuracy else { return }
        askedForFullAccuracy = true
        // The purpose key's text lives in Info.plist (NSLocationTemporaryUsageDescriptionDictionary).
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Guidance") { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let still = self.manager.accuracyAuthorization == .reducedAccuracy
                if still != self.isReducedAccuracy { self.isReducedAccuracy = still }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Perf.hit("locFix")
        fixCount += 1
        // Each @Published assignment redraws the screen, so only touch what actually changed.
        location = latest
        let newSpeed = max(0, latest.speed)
        if newSpeed != speed { speed = newSpeed }
        if errorMessage != nil { errorMessage = nil }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Perf.hit("headingFix")
        headingCount += 1
        if newHeading.headingAccuracy != headingAccuracy { headingAccuracy = newHeading.headingAccuracy }
        guard newHeading.headingAccuracy >= 0 else { return }
        let newHeadingValue = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if newHeadingValue != heading { heading = newHeadingValue }
    }

    /// Explicitly opt into iOS's own figure-8 calibration prompt when accuracy is poor,
    /// rather than leaving it to the implicit default — accurate heading is the whole
    /// point of a compass app.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient "can't fix right now" — CoreLocation keeps retrying on its own, so don't
        // scare the user with a permanent-looking error for a passing hiccup.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        errorMessage = error.localizedDescription
    }
}
