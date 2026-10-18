//
//  Proximity.swift
//  ThatWayCore
//
//  The platform-neutral half of "find a friend nearby": what the backend relays, how far-away is described in words
//  and haptics, and the smoothing that stops the readout flickering. The Nearby Interaction session itself lives in the
//  iPhone app (the watch only shows what the phone reports). Distances and bands only: no coordinates ever appear here.
//

import Foundation

/// The wire shape of `GET /nearby/offers`. `token` is an opaque base64 NearbyInteraction discovery token.
public struct NearbyOffer: Codable, Equatable, Sendable {
    public var friendId: String
    public var token: String
    public var kind: NearbyKind
    public var expiresAt: Double
    public init(friendId: String, token: String, kind: NearbyKind, expiresAt: Double) {
        self.friendId = friendId; self.token = token; self.kind = kind; self.expiresAt = expiresAt
    }
}

public enum NearbyKind: String, Codable, Sendable { case uwb, ble }

/// What this phone can do. Ultra Wideband needs the U1/U2 chip: every iPhone 11 and later except the iPhone SE range.
public enum NearbyCapability: Equatable, Sendable {
    /// Distance and direction (the arrow).
    case uwbWithDirection
    /// Distance only.
    case uwbDistanceOnly
    /// No Ultra Wideband (iPhone SE, simulator, older phones).
    case unsupported

    public var canRange: Bool { self != .unsupported }
}

/// How close, in words. Coarse on purpose: raw metres flicker, bands give stable haptics and speech.
public enum ProximityBand: Int, Comparable, Codable, Sendable {
    case here, veryClose, close, near, far

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Upper edge of each band in metres: here ≤ 1.5, veryClose ≤ 5, close ≤ 15, near ≤ 50, then far.
    public var upperBound: Double {
        switch self {
        case .here: return 1.5
        case .veryClose: return 5
        case .close: return 15
        case .near: return 50
        case .far: return .infinity
        }
    }

    public var label: String {
        switch self {
        case .here: return "Right here"
        case .veryClose: return "Very close"
        case .close: return "Close"
        case .near: return "Nearby"
        case .far: return "Farther away"
        }
    }

    public static func exact(forMeters meters: Double) -> ProximityBand {
        for band in [ProximityBand.here, .veryClose, .close, .near] where meters <= band.upperBound { return band }
        return .far
    }
}

/// Smooths the distance and keeps the band from flapping near an edge: the band only changes once the smoothed distance
/// is more than `hysteresis` (a fraction of the edge) past the edge it is leaving.
public struct ProximitySmoother: Sendable {
    public private(set) var meters: Double?
    public private(set) var band: ProximityBand?
    private let alpha: Double
    private let hysteresis: Double

    public init(alpha: Double = 0.35, hysteresis: Double = 0.12) {
        self.alpha = alpha; self.hysteresis = hysteresis
    }

    @discardableResult
    public mutating func add(meters raw: Double) -> ProximityBand {
        let smoothed = meters.map { $0 + alpha * (raw - $0) } ?? raw
        meters = smoothed
        let target = ProximityBand.exact(forMeters: smoothed)
        guard let current = band, current != target else { band = target; return target }
        if target > current {            // moving away: must clear the current band's outer edge by the margin
            if smoothed > current.upperBound * (1 + hysteresis) { band = target }
        } else {                         // moving closer: must be inside the target's outer edge by the margin
            if smoothed < target.upperBound * (1 - hysteresis) { band = target }
        }
        return band ?? target
    }

    public mutating func reset() { meters = nil; band = nil }
}

/// A reading ready to show: smoothed metres, the band, and the bearing of the friend relative to where the phone's top
/// points (degrees, −180…180, positive to the right) when the hardware can give one.
public struct ProximityReading: Equatable, Sendable {
    public var meters: Double
    public var band: ProximityBand
    public var relativeBearing: Double?
    public init(meters: Double, band: ProximityBand, relativeBearing: Double? = nil) {
        self.meters = meters; self.band = band; self.relativeBearing = relativeBearing
    }

    /// "12 m", or "Right here" under a metre and a half: never false precision.
    public var distanceText: String {
        if band == .here { return ProximityBand.here.label }
        let rounded = meters < 10 ? (meters * 2).rounded() / 2 : meters.rounded()
        return rounded == rounded.rounded() ? "\(Int(rounded)) m" : String(format: "%.1f m", rounded)
    }
}

/// Phone → watch: who is being found and how close. Rides on `WatchSync` as part of the application context, so it is
/// the same low-volume channel as the travel mode.
public struct ProximityWatchState: Equatable, Sendable {
    public var friendName: String
    public var band: ProximityBand
    public var meters: Int?
    public init(friendName: String, band: ProximityBand, meters: Int?) {
        self.friendName = friendName; self.band = band; self.meters = meters
    }
}

public extension WatchSync {
    static let proximityKey = "proximity"

    /// Pass nil to tell the watch the session ended (the key is sent as an empty dictionary).
    static func proximityPayload(_ state: ProximityWatchState?) -> [String: Any] {
        guard let state else { return [proximityKey: [String: Any]()] }
        var inner: [String: Any] = ["name": state.friendName, "band": state.band.rawValue]
        if let meters = state.meters { inner["m"] = meters }
        return [proximityKey: inner]
    }

    /// `.some(nil)` = the phone ended the session; `nil` = this payload says nothing about proximity.
    static func proximity(from payload: [String: Any]) -> ProximityWatchState?? {
        guard let inner = payload[proximityKey] as? [String: Any] else { return nil }
        guard let name = inner["name"] as? String,
              let raw = inner["band"] as? Int, let band = ProximityBand(rawValue: raw) else { return .some(nil) }
        return .some(ProximityWatchState(friendName: name, band: band, meters: inner["m"] as? Int))
    }
}
