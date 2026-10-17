//
//  Trace.swift
//  ThatWayCore
//
//  "Trace a friend": the position as the server relays it, and the fusion that turns a friend's GPS position
//  (any range, anywhere in the world) and, when close, an Ultra Wideband reading into one direction and distance.
//  (The permission model itself, who may trace whom and for how long, is in Grants.swift.)
//  Only direction and distance ever leave this file: nothing here draws, stores or prints a coordinate.
//

import Foundation
import CoreLocation

/// The friend's last position as the server relays it, with its age in seconds. Held in memory only.
public struct TracePeerPosition: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double?
    public var ageSeconds: Double

    public init(latitude: Double, longitude: Double, accuracy: Double? = nil, ageSeconds: Double) {
        self.latitude = latitude; self.longitude = longitude; self.accuracy = accuracy; self.ageSeconds = ageSeconds
    }

    enum CodingKeys: String, CodingKey { case latitude = "lat", longitude = "lon", accuracy = "acc", ageSeconds = "age" }

    public var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

public enum TraceSource: String, Sendable { case gps, uwb }

/// What the pill shows: how far, which way, how sure.
public struct TraceReading: Equatable, Sendable {
    public var meters: Double
    public var band: ProximityBand
    public var source: TraceSource
    /// True bearing from me to them (GPS only): the pill subtracts the live heading so the arrow turns with the phone.
    public var trueBearing: Double?
    /// Bearing relative to the top of the phone (UWB only).
    public var relativeBearing: Double?
    /// How old the friend's last position is; nil for UWB (live).
    public var peerAgeSeconds: Double?

    public init(meters: Double, band: ProximityBand, source: TraceSource, trueBearing: Double? = nil,
                relativeBearing: Double? = nil, peerAgeSeconds: Double? = nil) {
        self.meters = meters; self.band = band; self.source = source
        self.trueBearing = trueBearing; self.relativeBearing = relativeBearing; self.peerAgeSeconds = peerAgeSeconds
    }

    /// A friend position older than this is shown as "last seen" rather than live.
    public static let staleSeconds = 45.0

    public var isStale: Bool { (peerAgeSeconds ?? 0) > Self.staleSeconds }

    /// Arrow angle in degrees, positive clockwise from the top of the phone. Needs a heading for GPS readings.
    public func arrowAngle(heading: Double?) -> Double? {
        if let relativeBearing { return relativeBearing }
        guard let trueBearing, let heading else { return nil }
        return CompassManager.relativeBearing(heading: heading, bearing: trueBearing)
    }

    /// "Right here", "12 m", "3.4 km", "8,240 km": never false precision at range.
    public var distanceText: String {
        if source == .uwb, band == .here { return ProximityBand.here.label }
        if meters < 1000 {
            let r = meters < 10 ? (meters * 2).rounded() / 2 : meters.rounded()
            return r == r.rounded() ? "\(Int(r)) m" : String(format: "%.1f m", r)
        }
        let km = meters / 1000
        if km < 100 { return String(format: "%.1f km", km) }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; f.locale = Locale(identifier: "en_US")
        return (f.string(from: NSNumber(value: km.rounded())) ?? "\(Int(km))") + " km"
    }
}

/// GPS carries the whole journey; UWB takes over for the last stretch. Pure and deterministic: callers pass the clock.
public struct TraceFusion: Sendable {
    /// Start trying UWB inside this GPS distance (UWB itself only reaches about 10 to 20 m, so this is a head start).
    public static let uwbEngageMeters = 40.0
    /// Give UWB back to GPS beyond this (hysteresis so it does not flap at the edge).
    public static let uwbReleaseMeters = 60.0
    /// A UWB reading older than this no longer counts.
    public static let uwbFreshSeconds = 3.0

    private var smoother = ProximitySmoother()
    private var lastSource: TraceSource?

    public init() {}

    /// Whether the phone should be running a UWB session, given the latest GPS distance and whether one is running.
    public static func wantsUWB(gpsMeters: Double?, running: Bool) -> Bool {
        guard let gpsMeters else { return false }
        return running ? gpsMeters <= uwbReleaseMeters : gpsMeters <= uwbEngageMeters
    }

    public mutating func reset() { smoother.reset(); lastSource = nil }

    /// - Parameters:
    ///   - me: my position (nil until the first fix)
    ///   - peer: the friend's last relayed position
    ///   - uwb: the latest UWB reading and how old it is, if a session is ranging
    public mutating func reading(me: CLLocationCoordinate2D?, peer: TracePeerPosition?,
                                 uwb: (reading: ProximityReading, ageSeconds: Double)?) -> TraceReading? {
        if let uwb, uwb.ageSeconds <= Self.uwbFreshSeconds {
            if lastSource != .uwb { smoother.reset(); lastSource = .uwb }
            // The UWB reading is already smoothed by the session owner: pass it through, keep the band from flapping.
            let band = smoother.add(meters: uwb.reading.meters)
            return TraceReading(meters: smoother.meters ?? uwb.reading.meters, band: band, source: .uwb,
                                relativeBearing: uwb.reading.relativeBearing)
        }
        guard let me, let peer else { return nil }
        if lastSource != .gps { smoother.reset(); lastSource = .gps }
        let there = peer.coordinate
        let metres = CompassManager.distance(from: me, to: there)
        let band = smoother.add(meters: metres)
        return TraceReading(meters: smoother.meters ?? metres, band: band, source: .gps,
                            trueBearing: CompassManager.bearing(from: me, to: there), peerAgeSeconds: peer.ageSeconds)
    }
}
