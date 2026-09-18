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

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            start()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self, selector: #selector(deviceOrientationDidChange),
                name: UIDevice.orientationDidChangeNotification, object: nil
            )
            updateHeadingOrientation()
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// Keeps the heading reading correct regardless of how the phone is actually being
    /// held — flat like a real compass, in landscape, upside down, etc. Without this,
    /// `CLLocationManager` assumes portrait and heading drifts 90°+ off as soon as the
    /// phone is rotated, which matters a lot for an app you're meant to check mid-walk.
    @objc private func deviceOrientationDidChange() {
        updateHeadingOrientation()
    }

    private func updateHeadingOrientation() {
        switch UIDevice.current.orientation {
        case .portrait: manager.headingOrientation = .portrait
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: manager.headingOrientation = .landscapeLeft
        case .landscapeRight: manager.headingOrientation = .landscapeRight
        default: break // faceUp/faceDown/unknown: keep whatever orientation was last valid
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enable it in Settings to use the compass."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        speed = max(0, latest.speed)
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headingAccuracy = newHeading.headingAccuracy
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
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
