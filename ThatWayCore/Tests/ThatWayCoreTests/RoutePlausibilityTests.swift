import Testing
import CoreLocation
@testable import ThatWayCore

struct RoutePlausibilityTests {
    private let melbourne = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    private let perth = CLLocationCoordinate2D(latitude: -31.9505, longitude: 115.8605)
    private let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    private let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)

    @Test func anotherContinentIsNeverRouted() {
        for profile in TravelProfile.allCases {
            #expect(RoutePlausibility.check(from: melbourne, to: london, profile: profile) == .tooFar(limitKm: RoutePlausibility.limitKm(for: profile)))
        }
    }

    @Test func aLongRealDriveIsStillAllowed() {
        #expect(RoutePlausibility.check(from: melbourne, to: perth, profile: .driving) == .routable, "about 2,700 km in a straight line")
    }

    @Test func theLimitDependsOnHowYouTravel() {
        #expect(RoutePlausibility.check(from: melbourne, to: sydney, profile: .driving) == .routable)
        #expect(RoutePlausibility.check(from: melbourne, to: sydney, profile: .cycling) == .routable, "about 710 km")
        #expect(RoutePlausibility.check(from: melbourne, to: sydney, profile: .walking) == .tooFar(limitKm: 200))
    }

    @Test func nearbyIsAlwaysRoutable() {
        let near = CLLocationCoordinate2D(latitude: melbourne.latitude + 0.01, longitude: melbourne.longitude)
        #expect(RoutePlausibility.check(from: melbourne, to: near, profile: .walking) == .routable)
    }
}
