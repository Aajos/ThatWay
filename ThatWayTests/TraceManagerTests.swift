//
//  TraceManagerTests.swift
//  ThatWayTests
//
//  The consent flow and the radio handoff, against a fake server and a fake Ultra Wideband layer. What matters:
//  nothing is shared before the other person says yes; a dropped connection or a stale poll never ends or revives a
//  trace; ending always tells the server; UWB only runs when close and takes over from GPS only while it is fresh.
//

import Testing
import Foundation
import CoreLocation
@testable import ThatWay
import ThatWayCore

@MainActor
private final class FakeTraceAPI: TraceAPI {
    var sessions: [TraceSession] = []
    var failList = false
    var failRequest: Error?
    var requests: [String] = []
    var responses: [(friendId: String, accept: Bool)] = []
    var ended: [String] = []
    var positionsSent = 0
    /// Runs while a list call is "in flight", to model a poll that overlaps a local action.
    var duringList: (() async -> Void)?

    func traceRequest(friendId: String) async throws {
        if let failRequest { throw failRequest }
        requests.append(friendId)
    }
    func traceList() async throws -> [TraceSession] {
        let snapshot = sessions
        if let duringList { await duringList() }
        if failList { throw FriendsError.unreachable }
        return snapshot
    }
    func traceRespond(friendId: String, accept: Bool) async throws {
        responses.append((friendId, accept))
        // Like the real server: accepting makes the session active, declining removes my row.
        sessions = accept
            ? sessions.map { TraceSession(friendId: $0.friendId, status: .active, sessionId: $0.sessionId, expiresAt: $0.expiresAt) }
            : []
    }
    func tracePosition(friendId: String, coordinate: CLLocationCoordinate2D, accuracy: Double) async throws { positionsSent += 1 }
    func traceEnd(friendId: String) async { ended.append(friendId) }
}

@MainActor
private final class FakeRanging: ProximityRanging {
    var capability: NearbyCapability = .uwbWithDirection
    var latestReading: (reading: ProximityReading, at: Date)?
    var onReading: (() -> Void)?
    var started: [String] = []
    var stops = 0
    func start(with friend: Friend) { started.append(friend.id) }
    func stop() { stops += 1 }
}

@MainActor
private final class FakeNotifier: TraceNotifying {
    var authorizationRequests = 0
    var incoming: [String] = []
    var clears = 0
    func requestAuthorizationIfNeeded() { authorizationRequests += 1 }
    func incomingRequest(from name: String) { incoming.append(name) }
    func clearIncoming() { clears += 1 }
}

@MainActor
private final class Rig {
    let api = FakeTraceAPI(), ranging = FakeRanging(), notifier = FakeNotifier()
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var me: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    let bob = Friend(id: "bob-id", username: "bob", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
    var manager: TraceManager!

    var entitled = true

    init() {
        manager = TraceManager(
            api: api, ranging: ranging, notifier: notifier,
            friends: { [bob] in [bob] },
            myPosition: { [unowned self] in self.me },
            now: { [unowned self] in self.clock },
            sleep: { _ in },
            loopEnabled: false,
            isEntitled: { [unowned self] in self.entitled })
    }

    /// A position `metres` north of me, as the server would relay it.
    func peer(metres: Double, age: Double = 2) -> TracePeerPosition {
        let m = me ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return TracePeerPosition(latitude: m.latitude + metres / 111_320, longitude: m.longitude, accuracy: 8, ageSeconds: age)
    }

    func session(_ status: TraceStatus, peer: TracePeerPosition? = nil, id: String = "s1") -> TraceSession {
        TraceSession(friendId: "bob-id", status: status, sessionId: id, expiresAt: 9_999_999_999, peer: peer)
    }
}

@MainActor
struct TraceManagerTests {
    // MARK: Consent

    @Test func askingSendsOneRequestAndWaitsForTheAnswer() async {
        let r = Rig()
        await r.manager.request(r.bob)
        #expect(r.api.requests == ["bob-id"])
        #expect(r.manager.state == .asking(r.bob))
        #expect(r.notifier.authorizationRequests == 1)
        await r.manager.request(r.bob)
        #expect(r.api.requests.count == 1, "asking again while pending does nothing")
    }

    @Test func nothingIsSharedUntilTheyAccept() async {
        let r = Rig()
        await r.manager.request(r.bob)
        r.api.sessions = [r.session(.outgoing)]
        await r.manager.poll()
        #expect(r.manager.state == .asking(r.bob))
        #expect(r.api.positionsSent == 0, "no position before consent")
        #expect(r.ranging.started.isEmpty)
        #expect(r.manager.reading == nil)
    }

    @Test func acceptedMeansPositionsFlowAndTheReadingAppears() async {
        let r = Rig()
        await r.manager.request(r.bob)
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 5_000))]
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob))
        #expect(r.api.positionsSent == 1)
        let reading = r.manager.reading
        #expect(reading?.source == .gps)
        #expect((reading?.meters ?? 0) > 4_900 && (reading?.meters ?? 0) < 5_100)
    }

    @Test func anIncomingRequestShowsAndNotifiesOnceWhenTheAppIsNotInFront() async {
        let r = Rig()
        r.manager.setSceneActive(false)
        r.api.sessions = [r.session(.incoming)]
        await r.manager.poll()
        #expect(r.manager.state == .incoming(r.bob))
        #expect(r.notifier.incoming == ["bob"])
        await r.manager.poll()
        #expect(r.notifier.incoming == ["bob"], "one notification per request")
    }

    @Test func noNotificationWhileTheAppIsInFront() async {
        let r = Rig()
        r.manager.setSceneActive(true)
        r.api.sessions = [r.session(.incoming)]
        await r.manager.poll()
        #expect(r.manager.state == .incoming(r.bob))
        #expect(r.notifier.incoming.isEmpty, "the pill itself is the notification")
    }

    @Test func acceptAndDeclineAnswerTheServer() async {
        let r = Rig()
        r.api.sessions = [r.session(.incoming)]
        await r.manager.poll()
        await r.manager.accept()
        #expect(r.api.responses.first?.accept == true)
        #expect(r.manager.state == .active(r.bob))

        let d = Rig()
        d.api.sessions = [d.session(.incoming)]
        await d.manager.poll()
        await d.manager.decline()
        #expect(d.api.responses.first?.accept == false)
        #expect(d.manager.state == nil)
    }

    @Test func aDeclineIsShownOnceAndNeverComesBack() async {
        let r = Rig()
        await r.manager.request(r.bob)
        r.api.sessions = [r.session(.declined, id: "s9")]
        await r.manager.poll()
        #expect(r.manager.state == .notice("bob declined"))
        r.clock = r.clock.addingTimeInterval(6)
        await r.manager.poll()
        #expect(r.manager.state == nil, "the notice fades")
        #expect(r.manager.isBusy == false)
        await r.manager.poll()
        #expect(r.manager.state == nil, "the same declined row (kept by the server for a minute) is not shown again")
    }

    @Test func theOtherSideEndingIsReported() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 100))]
        await r.manager.poll()
        r.api.sessions = []
        await r.manager.poll()
        #expect(r.manager.state == .notice("bob ended the trace"))
        #expect(r.manager.reading == nil)
        #expect(r.ranging.stops >= 0)
    }

    @Test func requestFailureShowsAMessageAndLeavesNothingPending() async {
        let r = Rig()
        r.api.failRequest = FriendsError.server("Too many open requests")
        await r.manager.request(r.bob)
        #expect(r.manager.state == nil)
        #expect(r.manager.errorMessage == "Too many open requests")
    }

    // MARK: Ending, and the things that must not end or revive a trace

    @Test func endingTellsTheServerAndClearsEverything() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 20))]
        await r.manager.poll()
        await r.manager.end()
        #expect(r.api.ended == ["bob-id"])
        #expect(r.manager.state == nil)
        #expect(r.manager.reading == nil)
        #expect(r.ranging.stops >= 1, "the radio is stopped")
    }

    @Test func aPollThatWasInFlightCannotBringBackAnEndedTrace() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 100))]
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob))
        // The server still says ACTIVE for the poll that is in flight when the person taps stop.
        r.api.duringList = { [manager = r.manager!] in
            r.api.duringList = nil
            await manager.end()
        }
        await r.manager.poll()
        #expect(r.manager.state == nil, "the stale result is discarded")
    }

    @Test func aDroppedConnectionDoesNotEndATrace() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 100))]
        await r.manager.poll()
        r.api.failList = true
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob))
        #expect(r.manager.reading != nil)
    }

    @Test func signingOutDropsEverything() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 100))]
        await r.manager.poll()
        r.manager.reset()
        #expect(r.manager.state == nil)
        #expect(r.manager.reading == nil)
    }

    // MARK: Position sharing

    @Test func positionIsSharedSparingly() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 500))]
        await r.manager.poll()
        #expect(r.api.positionsSent == 1)
        r.clock = r.clock.addingTimeInterval(1)
        await r.manager.poll()
        #expect(r.api.positionsSent == 1, "not within 3 s")
        r.clock = r.clock.addingTimeInterval(4)
        await r.manager.poll()
        #expect(r.api.positionsSent == 1, "3 s passed but I have not moved")
        r.me = CLLocationCoordinate2D(latitude: r.me!.latitude + 0.0001, longitude: r.me!.longitude)   // about 11 m
        await r.manager.poll()
        #expect(r.api.positionsSent == 2, "moved")
        r.clock = r.clock.addingTimeInterval(16)
        await r.manager.poll()
        #expect(r.api.positionsSent == 3, "a keep-alive at least every 15 s")
    }

    @Test func noPositionIsSentWithoutAFix() async {
        let r = Rig()
        r.me = nil
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 500))]
        await r.manager.poll()
        #expect(r.api.positionsSent == 0)
    }

    // MARK: Ultra Wideband takes over up close

    @Test func theRadioStartsOnlyWhenClose() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 5_000))]
        await r.manager.poll()
        #expect(r.ranging.started.isEmpty, "far away: GPS only")
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 30))]
        await r.manager.poll()
        #expect(r.ranging.started == ["bob-id"])
        await r.manager.poll()
        #expect(r.ranging.started.count == 1, "started once")
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 50))]
        await r.manager.poll()
        #expect(r.ranging.stops == 0, "still inside the 60 m hysteresis")
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 200))]
        await r.manager.poll()
        #expect(r.ranging.stops == 1, "released when they are well away")
    }

    @Test func aPhoneWithoutUWBStaysOnGpsAtAnyDistance() async {
        let r = Rig()
        r.ranging.capability = .unsupported
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 10))]
        await r.manager.poll()
        #expect(r.ranging.started.isEmpty)
        #expect(r.manager.reading?.source == .gps)
    }

    @Test func aFreshRadioReadingTakesOverAndGpsReturnsWhenItGoesStale() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 25))]
        await r.manager.poll()
        r.ranging.latestReading = (ProximityReading(meters: 3.2, band: .veryClose, relativeBearing: 40), r.clock)
        r.ranging.onReading?()
        #expect(r.manager.reading?.source == .uwb)
        #expect(r.manager.reading?.relativeBearing == 40)
        r.clock = r.clock.addingTimeInterval(10)
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 25))]
        await r.manager.poll()
        #expect(r.manager.reading?.source == .gps, "radio readings older than 3 s no longer count")
    }

    // MARK: The paid switch

    @Test func withoutTheEntitlementAskingShowsThePaywallAndSendsNothing() async {
        let r = Rig(); r.entitled = false
        await r.manager.request(r.bob)
        #expect(r.api.requests.isEmpty)
        #expect(r.manager.needsUpgrade)
        #expect(r.manager.state == nil)
    }

    @Test func withoutTheEntitlementAcceptingAndFollowingAreBlockedButDecliningIsNot() async {
        let r = Rig(); r.entitled = false
        r.api.sessions = [r.session(.incoming)]
        await r.manager.poll()
        await r.manager.accept()
        #expect(r.api.responses.isEmpty, "accepting is paid")
        #expect(r.manager.needsUpgrade)
        r.manager.needsUpgrade = false
        await r.manager.decline()
        #expect(r.api.responses.first?.accept == false, "declining is always free")

        let f = Rig(); f.entitled = false
        f.api.sessions = [f.session(.active, peer: f.peer(metres: 1_000))]
        await f.manager.poll()
        var followed = 0
        f.manager.onFollow = { _, _, _ in followed += 1 }
        f.manager.follow(guide: true)
        #expect(followed == 0 && f.manager.needsUpgrade)
    }

    @Test func payingTurnsEverythingOn() async {
        let r = Rig()
        await r.manager.request(r.bob)
        #expect(r.api.requests == ["bob-id"])
        #expect(r.manager.needsUpgrade == false)
    }

    // MARK: Following a friend (point and guide)

    @Test func followingNeedsAnActiveTraceWithAPosition() async {
        let r = Rig()
        var followed: [(String, Bool)] = []
        r.manager.onFollow = { friend, _, guide in followed.append((friend.id, guide)) }
        r.manager.follow(guide: true)
        #expect(followed.isEmpty, "nothing to follow before a trace is active")

        r.api.sessions = [r.session(.active, peer: r.peer(metres: 3_000))]
        await r.manager.poll()
        r.manager.follow(guide: false)
        r.manager.follow(guide: true)
        #expect(followed.count == 2 && followed[0].1 == false && followed[1].1 == true)
        #expect(r.manager.following == "bob-id")
    }

    @Test func theFollowedFriendsPositionIsPassedOnEachPoll() async {
        let r = Rig()
        var positions = 0
        r.manager.onFriendPosition = { _, _ in positions += 1 }
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 3_000))]
        await r.manager.poll()
        #expect(positions == 0, "not following yet")
        r.manager.follow(guide: false)
        await r.manager.poll()
        #expect(positions == 1)
    }

    @Test func theTraceEndingStopsFollowing() async {
        let r = Rig()
        var stopped = 0
        r.manager.onStopFollowing = { stopped += 1 }
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 3_000))]
        await r.manager.poll()
        r.manager.follow(guide: true)
        r.api.sessions = []
        await r.manager.poll()
        #expect(stopped == 1)
        #expect(r.manager.following == nil)
    }

    @Test func sharingIsTrueOnlyWhileActive() async {
        let r = Rig()
        #expect(r.manager.isSharing == false)
        await r.manager.request(r.bob)
        #expect(r.manager.isSharing == false, "asking shares nothing")
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 500))]
        await r.manager.poll()
        #expect(r.manager.isSharing)
        await r.manager.end()
        #expect(r.manager.isSharing == false)
    }

    // MARK: What the person is shown

    @Test func theReadingCarriesDistanceAndDirectionNotACoordinate() async {
        let r = Rig()
        r.api.sessions = [r.session(.active, peer: r.peer(metres: 2_000))]
        await r.manager.poll()
        let reading = r.manager.reading
        #expect(reading?.distanceText == "2.0 km")
        let b = reading?.trueBearing ?? -1
        #expect(b < 1 || b > 359, "due north")
        // The only things a TraceReading holds are numbers about distance and direction.
        let mirror = Mirror(reflecting: reading!).children.compactMap { $0.label }
        #expect(!mirror.contains("latitude") && !mirror.contains("longitude") && !mirror.contains("coordinate"))
    }
}
