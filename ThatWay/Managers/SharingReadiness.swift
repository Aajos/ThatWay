//
//  SharingReadiness.swift
//  ThatWay
//
//  Can this phone actually share its location with a friend? Checked before someone allows a trace (so nobody says yes to
//  something their settings would quietly break) and shown in the banner while a trace is live.
//
//  "While Using the App" is enough: during a trace the phone keeps sharing in the background with the blue indicator, as the
//  consent says. "Always" is never needed. Precise Location is: without it iOS blurs the position by kilometres.
//  "Allow Once" cannot be told apart from "While Using" while it lasts; when it lapses iOS reports "not asked" again, and that
//  case asks again here.
//

import CoreLocation
import UIKit

enum SharingReadiness: Equatable {
    case ready
    /// Never asked, or an "Allow Once" that has lapsed: iOS will show its own prompt.
    case notAsked
    /// Location is off for ThatWay (or for the whole phone, or restricted): only Settings can change it.
    case off
    /// Precise Location is off.
    case imprecise

    static func from(status: CLAuthorizationStatus, reducedAccuracy: Bool) -> SharingReadiness {
        switch status {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .off
        case .authorizedWhenInUse, .authorizedAlways: return reducedAccuracy ? .imprecise : .ready
        @unknown default: return .off
        }
    }

    /// What the person is told, in one or two sentences, before they can allow a trace.
    func explanation(name: String) -> String {
        switch self {
        case .ready: return ""
        case .notAsked:
            return "To share your location with \(name), ThatWay needs to use it. Choose “Allow While Using App” on the next screen: that is enough, and the trace still ends at the time you choose."
        case .off:
            return "Location is turned off for ThatWay, so \(name) couldn’t see where you are. In Settings, set Location to “While Using the App” and turn on Precise Location."
        case .imprecise:
            return "Precise Location is off for ThatWay, so \(name) would only see a rough area, kilometres wide. In Settings, under Location, turn on Precise Location."
        }
    }

    var buttonTitle: String { self == .notAsked ? "Allow location" : "Open Settings" }

    /// The one line in the banner while a trace is live and sharing has stopped.
    var bannerText: String {
        switch self {
        case .ready: return ""
        case .notAsked, .off: return "Sharing paused: location is off for ThatWay"
        case .imprecise: return "Sharing paused: Precise Location is off"
        }
    }

    /// Fix it the only way iOS allows: its own prompt when that is still possible, otherwise this app's page in Settings.
    @MainActor
    func fix(using location: LocationManager) {
        if self == .notAsked {
            location.requestPermission()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

extension LocationManager {
    var sharingReadiness: SharingReadiness { .from(status: authorizationStatus, reducedAccuracy: isReducedAccuracy) }
}
