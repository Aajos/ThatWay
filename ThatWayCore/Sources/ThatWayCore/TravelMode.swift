//
//  TravelMode.swift
//  ThatWayCore
//
//  The user's manually-selected travel mode — the one source of truth for which routing
//  profile to request, what distance tolerances to navigate with, and what the carousel
//  shows. Selection is authoritative: nothing here is ever inferred from detected speed.
//

import Foundation
import CoreLocation

/// Driving, walking or cycling — the routing profile a travel mode maps to. (Which URL serves each
/// profile is the iOS app's business: see `Config` / the app's `TravelProfile` extension.)
public enum TravelProfile: String, CaseIterable {
    case driving, walking, cycling

    public var displayName: String {
        switch self {
        case .driving: return "driving"
        case .walking: return "walking"
        case .cycling: return "cycling"
        }
    }
}

public enum TravelMode: String, Codable, CaseIterable {
    case walk, run, cycle, drive

    /// Walk and run share the walking routing profile — there's no separate running dataset.
    public var profile: TravelProfile {
        switch self {
        case .walk, .run: return .walking
        case .cycle: return .cycling
        case .drive: return .driving
        }
    }

    public var displayName: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .drive: return "Drive"
        }
    }

    public var symbolName: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Walk/run/cycle are all "on-foot" family for colour purposes (green); drive is its own
    /// (blue). See `AppTheme.modeOnFoot`/`modeDrive`.
    public var isOnFoot: Bool { self != .drive }

    public var tuning: ModeTuning { ModeTuning.table[self]! }

    /// Lets iOS tune GPS power use and filtering to how the user is moving.
    public var locationActivityType: CLActivityType { self == .drive ? .automotiveNavigation : .fitness }
}

/// Every distance/timing threshold the app used to hardcode for driving, now keyed per mode.
/// Driving's values are unchanged from before this struct existed; walk/run/cycle are
/// starting points roughly an order of magnitude smaller, to be tuned on foot.
public struct ModeTuning {
    /// Off-route / step-advance tolerance (perpendicular distance from the route line).
    public let corridorRadius: CLLocationDistance
    /// Location-check poll cadence.
    public let pollInterval: TimeInterval
    /// How close to the destination the route polyline is revealed.
    public let polylineRevealDistance: CLLocationDistance
    /// Distance beyond which the phase text reads "Continue" instead of "Coming up"/"Get ready".
    public let farCutoff: CLLocationDistance
    /// Distance within which the compass dial's hard tilt setting engages.
    public let hardTiltEngageDistance: CLLocationDistance
    /// Arrival radius.
    public let arrivalRadius: CLLocationDistance
    /// How close to the route's start still counts as "at the start".
    public let startSnapRadius: CLLocationDistance
    /// `GuidanceLineView`'s minimum real-distance spacing between redrawn polyline nodes.
    public let tier2MinSpacing: CLLocationDistance
    /// GPS distance filter (metres of movement before a new fix is delivered) while the next turn
    /// is far away, and within `precisionRadius` of it.
    public let farDistanceFilter: CLLocationDistance
    public let nearDistanceFilter: CLLocationDistance
    /// Within this distance of the next turn/destination GPS runs at full accuracy.
    public let precisionRadius: CLLocationDistance

    public init(corridorRadius: CLLocationDistance, pollInterval: TimeInterval, polylineRevealDistance: CLLocationDistance, farCutoff: CLLocationDistance,
                hardTiltEngageDistance: CLLocationDistance, arrivalRadius: CLLocationDistance, startSnapRadius: CLLocationDistance,
                tier2MinSpacing: CLLocationDistance, farDistanceFilter: CLLocationDistance, nearDistanceFilter: CLLocationDistance,
                precisionRadius: CLLocationDistance) {
        self.corridorRadius = corridorRadius; self.pollInterval = pollInterval; self.polylineRevealDistance = polylineRevealDistance
        self.farCutoff = farCutoff; self.hardTiltEngageDistance = hardTiltEngageDistance; self.arrivalRadius = arrivalRadius
        self.startSnapRadius = startSnapRadius; self.tier2MinSpacing = tier2MinSpacing; self.farDistanceFilter = farDistanceFilter
        self.nearDistanceFilter = nearDistanceFilter; self.precisionRadius = precisionRadius
    }

    // tier2MinSpacing carries over the pre-Phase-2b GuidanceLineView constants exactly for
    // walk (was "walking", 40m) and drive (was "driving", 60m); run/cycle interpolate.
    public static let table: [TravelMode: ModeTuning] = [
        .walk: ModeTuning(corridorRadius: 15, pollInterval: 10, polylineRevealDistance: 50, farCutoff: 100, hardTiltEngageDistance: 100, arrivalRadius: 5, startSnapRadius: 15, tier2MinSpacing: 40, farDistanceFilter: 6, nearDistanceFilter: 3, precisionRadius: 100),
        .run: ModeTuning(corridorRadius: 20, pollInterval: 7, polylineRevealDistance: 70, farCutoff: 150, hardTiltEngageDistance: 150, arrivalRadius: 6, startSnapRadius: 20, tier2MinSpacing: 45, farDistanceFilter: 8, nearDistanceFilter: 4, precisionRadius: 150),
        .cycle: ModeTuning(corridorRadius: 25, pollInterval: 5, polylineRevealDistance: 100, farCutoff: 300, hardTiltEngageDistance: 300, arrivalRadius: 10, startSnapRadius: 30, tier2MinSpacing: 50, farDistanceFilter: 12, nearDistanceFilter: 5, precisionRadius: 250),
        .drive: ModeTuning(corridorRadius: 30, pollInterval: 3, polylineRevealDistance: 500, farCutoff: 1000, hardTiltEngageDistance: 1000, arrivalRadius: 5, startSnapRadius: 50, tier2MinSpacing: 60, farDistanceFilter: 20, nearDistanceFilter: 8, precisionRadius: 400),
    ]
}

// MARK: - Apple Watch

public extension TravelMode {
    /// The modes the watch offers. Driving is deliberately absent: glancing at a wrist while driving is unsafe.
    static let watchModes: [TravelMode] = [.walk, .run, .cycle]

    /// False for driving: the watch refuses to guide and closes.
    var isSafeOnWatch: Bool { self != .drive }

    /// The next (`steps` > 0) or previous (`steps` < 0) watch mode, wrapping around. Driving, which the watch never
    /// offers, steps to walk.
    func onWatch(steps: Int) -> TravelMode {
        guard let index = Self.watchModes.firstIndex(of: self) else { return .walk }
        let count = Self.watchModes.count
        return Self.watchModes[((index + steps) % count + count) % count]
    }
}
