import Testing
import Foundation
@testable import ThatWayCore

struct ProximityTests {
    @Test func bandsFollowTheEdges() {
        #expect(ProximityBand.exact(forMeters: 0.5) == .here)
        #expect(ProximityBand.exact(forMeters: 1.5) == .here)
        #expect(ProximityBand.exact(forMeters: 3) == .veryClose)
        #expect(ProximityBand.exact(forMeters: 15) == .close)
        #expect(ProximityBand.exact(forMeters: 49.9) == .near)
        #expect(ProximityBand.exact(forMeters: 300) == .far)
        #expect(ProximityBand.here < ProximityBand.far)
    }

    @Test func smootherDoesNotFlapAtAnEdge() {
        var s = ProximitySmoother(alpha: 1, hysteresis: 0.12)   // no smoothing: isolates the hysteresis
        s.add(meters: 4.9)
        #expect(s.band == .veryClose)
        // Wobbling around 5 m must not flip the band back and forth.
        for d in [5.1, 4.9, 5.2, 4.8, 5.3] { s.add(meters: d) }
        #expect(s.band == .veryClose)
        // A clear move away does.
        s.add(meters: 6)
        #expect(s.band == .close)
        // And a clear move back in.
        s.add(meters: 4)
        #expect(s.band == .veryClose)
    }

    @Test func smootherAveragesNoise() {
        var s = ProximitySmoother(alpha: 0.35)
        for d in [10.0, 10, 10, 10] { s.add(meters: d) }
        s.add(meters: 20)           // one wild sample
        #expect((s.meters ?? 0) < 14)
        s.reset()
        #expect(s.meters == nil && s.band == nil)
    }

    @Test func distanceTextNeverClaimsFalsePrecision() {
        #expect(ProximityReading(meters: 0.9, band: .here).distanceText == "Right here")
        #expect(ProximityReading(meters: 3.26, band: .veryClose).distanceText == "3.5 m")
        #expect(ProximityReading(meters: 12.4, band: .close).distanceText == "12 m")
    }

    @Test func capabilityGatesRanging() {
        #expect(NearbyCapability.uwbWithDirection.canRange)
        #expect(NearbyCapability.uwbDistanceOnly.canRange)
        #expect(!NearbyCapability.unsupported.canRange)
    }

    @Test func watchPayloadRoundTripsAndCanEnd() {
        let state = ProximityWatchState(friendName: "sam", band: .close, meters: 12)
        let payload = WatchSync.proximityPayload(state)
        #expect(WatchSync.proximity(from: payload) == .some(state))
        #expect(WatchSync.proximity(from: WatchSync.proximityPayload(nil)) == .some(nil))
        #expect(WatchSync.proximity(from: ["travelMode": "walk"]) == nil, "an unrelated payload says nothing")
        #expect(WatchSync.mode(from: payload) == nil, "a proximity payload carries no travel mode")
    }

    @Test func offerDecodesFromTheBackendShape() throws {
        let json = #"[{"friendId":"abc","token":"QUJD","kind":"uwb","expiresAt":1700000000}]"#.data(using: .utf8)!
        let offers = try JSONDecoder().decode([NearbyOffer].self, from: json)
        #expect(offers == [NearbyOffer(friendId: "abc", token: "QUJD", kind: .uwb, expiresAt: 1_700_000_000)])
    }
}
