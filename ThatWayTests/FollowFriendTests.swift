//
//  FollowFriendTests.swift
//  ThatWayTests
//
//  A traced friend as a destination: Point works at any range with no route at all; Guidance chases a person who is
//  moving, re-fetching the road route only when they have moved enough, and never more than once every 20 seconds.
//

import Testing
import Foundation
import CoreLocation
import ThatWayCore
@testable import ThatWay

@MainActor
@Suite(.serialized)      // these share the saved-trip file and preferences with the rest of the app
struct FollowFriendTests {
    private let sam = Friend(id: "sam-id", username: "sam", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
    private let start = CLLocationCoordinate2D(latitude: -37.8, longitude: 144.9)

    /// A short route that starts where the test user is, so off-route detection stays out of the way of the count.
    private static let nearRoute: Route = {
        let here = AppModel.mockUserLocation
        return Route(
            geometry: (0...10).map { CLLocationCoordinate2D(latitude: here.latitude, longitude: here.longitude + Double($0) * 0.00002) },
            distance: 150, duration: 100, steps: [], segmentDurations: [], segmentSpeeds: [])
    }()

    private func make() -> (AppModel, MockRoutingProvider, Clock) {
        let provider = MockRoutingProvider(alwaysSucceedingWith: Self.nearRoute)
        let app = AppModel(routingManager: RoutingManager(provider: provider))
        app.clearDestination()
        let clock = Clock()
        app.followClock = { clock.now }
        return (app, provider, clock)
    }

    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    private func settle() async { try? await Task.sleep(for: .milliseconds(120)) }

    /// Waits (up to 3 s) for a count to reach a value, so the test does not depend on how busy the machine is.
    private func until(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func north(_ c: CLLocationCoordinate2D, metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + metres / 111_320, longitude: c.longitude)
    }

    @Test func pointModeFollowsAtAnyRangeWithoutFetchingARoute() async {
        let (app, provider, _) = make()
        let faraway = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)       // London
        app.followFriend(sam, at: faraway, guide: false)
        await settle()
        #expect(app.dest == "sam")
        #expect(app.guiding == false)
        #expect(app.isIdle == false)
        #expect(app.destinationCoordinate?.latitude == faraway.latitude)
        #expect(provider.callCount == 0, "no road route is asked for just to point at someone")
    }

    @Test func theNeedleTargetMovesWithTheFriend() {
        let (app, _, _) = make()
        app.followFriend(sam, at: start, guide: false)
        let moved = north(start, metres: 300)
        app.friendMoved(to: moved)
        #expect(app.destinationCoordinate?.latitude == moved.latitude)
    }

    @Test func guidingFetchesOnceAndThenChasesOnlyWhenTheyMoveEnough() async {
        let (app, provider, clock) = make()
        app.followFriend(sam, at: start, guide: true)
        await settle()
        #expect(app.guiding)
        await settle()
        let first = provider.callCount
        #expect(first >= 1)

        app.friendMoved(to: north(start, metres: 20))                  // barely moved
        clock.now = clock.now.addingTimeInterval(30)
        await settle()
        #expect(provider.callCount == first, "a small move is not worth a route")

        app.friendMoved(to: north(start, metres: 800))                 // moved a lot, and 30 s have passed
        await until(provider.callCount == first + 1)
        await until(!app.routingManager.isLoading)
        #expect(provider.callCount == first + 1, "a big move re-routes")

        app.friendMoved(to: north(start, metres: 2_000))               // moved a lot again, but only just re-routed
        await settle()
        #expect(provider.callCount == first + 1, "never more than once every 20 s")

        clock.now = clock.now.addingTimeInterval(25)
        app.friendMoved(to: north(start, metres: 2_400))
        await until(provider.callCount == first + 2)
        #expect(provider.callCount == first + 2, "and again once the interval has passed")
    }

    @Test func aRouteToAMovingFriendIsNeverSavedForRelaunch() async {
        let (app, _, _) = make()
        app.followFriend(sam, at: start, guide: true)
        await settle()
        #expect(RoutePersistence.load() == nil, "relaunching must not resurrect a stale place")
    }

    @Test func clearingTheDestinationStopsFollowing() {
        let (app, _, _) = make()
        app.followFriend(sam, at: start, guide: false)
        app.clearDestination()
        #expect(app.isIdle)
        app.friendMoved(to: north(start, metres: 500))
        #expect(app.destinationCoordinate == nil, "no longer chasing anyone")
    }

    @Test func arrivingAtAFriendFinishesLikeAnyTrip() {
        let (app, _, _) = make()
        app.followFriend(sam, at: start, guide: false)
        app.mode = .guidance
        app.arrived = true
        app.finishArrival()
        #expect(app.isIdle)
        #expect(app.destinationCoordinate == nil)
    }
}
