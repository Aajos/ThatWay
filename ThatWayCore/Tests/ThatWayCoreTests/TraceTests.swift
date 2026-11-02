import Testing
import Foundation
import CoreLocation
@testable import ThatWayCore

struct TraceTests {
    private let melbourne = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    private let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)

    private func peer(_ c: CLLocationCoordinate2D, age: Double = 2) -> TracePeerPosition {
        TracePeerPosition(latitude: c.latitude, longitude: c.longitude, accuracy: 8, ageSeconds: age)
    }

    @Test func worksAtAnyRangeIncludingIntercontinental() throws {
        var f = TraceFusion()
        let r0 = f.reading(me: melbourne, peer: peer(london), uwb: nil)
        let r = try #require(r0)
        #expect(r.source == .gps)
        #expect(r.meters > 16_000_000 && r.meters < 17_500_000, "Melbourne to London is about 16,900 km")
        #expect(r.band == .far)
        #expect(r.distanceText.hasSuffix(" km") && r.distanceText.contains(","))
        let bearing = try #require(r.trueBearing)
        #expect(bearing >= 0 && bearing < 360)
    }

    @Test func localRangeReadsInMetres() throws {
        var f = TraceFusion()
        let near = CLLocationCoordinate2D(latitude: melbourne.latitude + 0.0001, longitude: melbourne.longitude)   // about 11 m
        let r0 = f.reading(me: melbourne, peer: peer(near), uwb: nil)
        let r = try #require(r0)
        #expect(r.meters > 9 && r.meters < 13)
        #expect(r.distanceText.hasSuffix(" m"))
        #expect(r.band == .close)
    }

    @Test func uwbTakesOverWhenFreshAndGpsTakesBackWhenItGoesStale() throws {
        var f = TraceFusion()
        let near = CLLocationCoordinate2D(latitude: melbourne.latitude + 0.0002, longitude: melbourne.longitude)
        let uwb = ProximityReading(meters: 4.2, band: .veryClose, relativeBearing: 30)
        let a0 = f.reading(me: melbourne, peer: peer(near), uwb: (uwb, 0.5))
        let a = try #require(a0)
        #expect(a.source == .uwb)
        #expect(a.relativeBearing == 30)
        #expect(abs(a.meters - 4.2) < 0.01, "UWB's own number, not GPS's")
        let b0 = f.reading(me: melbourne, peer: peer(near), uwb: (uwb, 5))
        let b = try #require(b0)
        #expect(b.source == .gps, "a UWB reading older than 3 s no longer counts")
        #expect(b.meters > 15, "back to GPS: about 22 m")
    }

    @Test func noPositionAndNoUwbMeansNoReading() {
        var f = TraceFusion()
        #expect(f.reading(me: melbourne, peer: nil, uwb: nil) == nil)
        #expect(f.reading(me: nil, peer: peer(london), uwb: nil) == nil)
    }

    @Test func uwbEngagementHasHysteresis() {
        #expect(TraceFusion.wantsUWB(gpsMeters: 150, running: false), "starts early, so it is connected by the time it is in range")
        #expect(!TraceFusion.wantsUWB(gpsMeters: 250, running: false), "not yet")
        #expect(TraceFusion.wantsUWB(gpsMeters: 250, running: true), "keeps going until 300 m")
        #expect(!TraceFusion.wantsUWB(gpsMeters: 320, running: true))
        #expect(!TraceFusion.wantsUWB(gpsMeters: nil, running: false))
    }

    @Test func arrowFollowsTheHeadingForGpsAndTheDeviceForUwb() {
        let gps = TraceReading(meters: 5000, band: .far, source: .gps, trueBearing: 90, peerAgeSeconds: 2)
        #expect(gps.arrowAngle(heading: 0) == 90)
        #expect(gps.arrowAngle(heading: 90) == 0, "facing them: straight ahead")
        #expect(gps.arrowAngle(heading: 270) == 180, "facing away")
        #expect(gps.arrowAngle(heading: nil) == nil, "no heading, no arrow")
        let uwb = TraceReading(meters: 4, band: .veryClose, source: .uwb, relativeBearing: -25)
        #expect(uwb.arrowAngle(heading: nil) == -25)
    }

    @Test func staleFriendIsFlagged() {
        #expect(TraceReading(meters: 1, band: .here, source: .gps, peerAgeSeconds: 60).isStale)
        #expect(!TraceReading(meters: 1, band: .here, source: .gps, peerAgeSeconds: 5).isStale)
        #expect(!TraceReading(meters: 1, band: .here, source: .uwb).isStale)
    }

    @Test func gpsCannotTellDirectionAtShortRange() {
        // Two phones 20 m apart, each ±10 m: the true direction could be 45 degrees either side. No honest arrow.
        #expect(TraceReading.uncertainty(meters: 20, myAccuracy: 10, peerAccuracy: 10) == 45)
        let near = TraceReading(meters: 20, band: .near, source: .gps, trueBearing: 10, uncertaintyDegrees: 45)
        #expect(!near.hasUsefulDirection)
        // 1 km apart with the same accuracy: about 1 degree. A real arrow.
        let far = TraceReading(meters: 1000, band: .far, source: .gps, trueBearing: 10,
                               uncertaintyDegrees: TraceReading.uncertainty(meters: 1000, myAccuracy: 10, peerAccuracy: 10))
        #expect(far.hasUsefulDirection && (far.uncertaintyDegrees ?? 99) < 2)
        #expect(TraceReading.uncertainty(meters: 0, myAccuracy: 5, peerAccuracy: 5) == 180)
    }

    @Test func aRadioReadingWithoutAnAngleHasNoDirection() {
        #expect(!TraceReading(meters: 3, band: .veryClose, source: .uwb).hasUsefulDirection, "distance only: warmer/colder, never a fake arrow")
        #expect(TraceReading(meters: 3, band: .veryClose, source: .uwb, relativeBearing: 20).hasUsefulDirection)
    }

    @Test func theFusionAttachesTheUncertainty() {
        var fusion = TraceFusion()
        let me = CLLocationCoordinate2D(latitude: -37.8, longitude: 145.0)
        let peer = TracePeerPosition(latitude: -37.8 + 30 / 111_320, longitude: 145.0, accuracy: 20, ageSeconds: 5)
        let r = fusion.reading(me: me, peer: peer, uwb: nil, myAccuracy: 20)
        #expect((r?.uncertaintyDegrees ?? 0) > 50 && r?.hasUsefulDirection == false)
    }
}
