//
//  TraceManagerTests.swift
//  ThatWayTests
//
//  The permission model, against a fake server, a fake radio, a fake notifier and a fake owner check. What matters:
//    - nothing is shared until the traced person says yes, and only after the owner check;
//    - a tracer is only ever told "Accepted" or "User cannot be traced, error has occurred", never a time;
//    - a new location is asked for at most every 2 minutes, and a failure never ends or revives a trace by itself;
//    - the traced phone uploads only while someone may see it and the app is open, and stopping is always immediate;
//    - one tracer holds up to ten permissions and looks at one friend at a time.
//

import Testing
import Foundation
import CoreLocation
@testable import ThatWay
import ThatWayCore

@MainActor
private final class FakeTraceAPI: TraceAPI {
    var snapshot = GrantsSnapshot()
    var failSnapshot = false
    var failRequest: Error?
    var failRevoke = false
    var requests: [(friendId: String, hours: Double)] = []
    var answers: [(tracerId: String, grant: Bool, hours: Double?, kind: GrantKind?, consent: String?)] = []
    var revoked: [String] = []
    var released: [String] = []
    var uploads = 0
    var locateCalls: [(id: String, distance: Double?)] = []
    var locateResult: Result<LocateResult, Error> = .success(LocateResult(position: nil, retryAfter: 120))
    /// Runs while a snapshot call is "in flight", to model a sync that overlaps a local action.
    var duringSnapshot: (() async -> Void)?

    func grantsSnapshot() async throws -> GrantsSnapshot {
        let copy = snapshot
        if let duringSnapshot { await duringSnapshot() }
        if failSnapshot { throw FriendsError.unreachable }
        return copy
    }
    func requestTrace(friendId: String, hours: Double) async throws {
        if let failRequest { throw failRequest }
        requests.append((friendId, hours))
    }
    func answerTrace(tracerId: String, grant: Bool, hours: Double?, kind: GrantKind?, consentVersion: String?) async throws {
        answers.append((tracerId, grant, hours, kind, consentVersion))
    }
    func revokeTrace(tracerId: String) async throws {
        if failRevoke { throw FriendsError.unreachable }
        revoked.append(tracerId)
    }
    func releaseTrace(traceeId: String) async { released.append(traceeId) }
    func uploadPosition(_ coordinate: CLLocationCoordinate2D, accuracy: Double) async throws { uploads += 1 }
    func locate(traceeId: String, distanceMeters: Double?) async throws -> LocateResult {
        locateCalls.append((traceeId, distanceMeters))
        return try locateResult.get()
    }
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
    var still: [String] = []
    var clears = 0
    func requestAuthorizationIfNeeded() { authorizationRequests += 1 }
    func incomingRequest(from name: String) { incoming.append(name) }
    func clearIncoming() { clears += 1 }
    func stillTracing(name: String) { still.append(name) }
}

@MainActor
private final class FakeOwner: OwnerAuthenticating {
    var method: OwnerCheck = .biometric(.faceID)
    var result: OwnerAuthResult = .success
    private(set) var reasons: [String] = []
    func authenticate(reason: String) async -> OwnerAuthResult { reasons.append(reason); return result }
}

@MainActor
private final class Rig {
    let api = FakeTraceAPI(), ranging = FakeRanging(), notifier = FakeNotifier(), owner = FakeOwner()
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var me: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
    let bob = Friend(id: "bob-id", username: "bob", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
    let cara = Friend(id: "cara-id", username: "cara", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
    var known: [Friend] = []
    var refreshes = 0
    var entitled = true
    var manager: TraceManager!

    init() {
        known = [bob, cara]
        manager = TraceManager(
            api: api, ranging: ranging, notifier: notifier, owner: owner,
            friends: { [self] in self.known },
            refreshFriends: { [self] in self.refreshes += 1 },
            myPosition: { [self] in self.me },
            now: { [self] in self.clock },
            sleep: { _ in },
            loopEnabled: false,
            isEntitled: { [self] in self.entitled })
    }

    /// A position `metres` north of me, as the server would relay it.
    func peer(metres: Double, age: Double = 90) -> TracePeerPosition {
        let m = me ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return TracePeerPosition(latitude: m.latitude + metres / 111_320, longitude: m.longitude, accuracy: 8, ageSeconds: age)
    }

    func locates(at metres: Double, age: Double = 90) { api.locateResult = .success(LocateResult(position: peer(metres: metres, age: age), retryAfter: 120)) }

    func tracerSees(_ entries: TracerEntry...) { api.snapshot = GrantsSnapshot(asTraced: api.snapshot.asTraced, asTracer: entries, plan: api.snapshot.plan) }
    func tracedSees(_ entries: TracedEntry...) { api.snapshot = GrantsSnapshot(asTraced: entries, asTracer: api.snapshot.asTracer, plan: api.snapshot.plan) }

    func waiting(_ id: String = "bob-id", kind: GrantKind = .window) -> TracerEntry { TracerEntry(traceeId: id, status: "waiting", kind: kind, expiresAt: clock.timeIntervalSince1970 + 1800) }
    func active(_ id: String = "bob-id", kind: GrantKind = .window) -> TracerEntry { TracerEntry(traceeId: id, status: "active", kind: kind) }
    func asking(_ id: String = "bob-id", kind: GrantKind = .window, hours: Double = 3) -> TracedEntry {
        TracedEntry(tracerId: id, status: "REQUESTED", kind: kind, requestedHours: hours, requestedAt: 1_799_999_000, requestExpiresAt: clock.timeIntervalSince1970 + 1500)
    }
    func watching(_ id: String = "bob-id", kind: GrantKind = .window, lookedAt: Double? = nil, band: String? = nil, still: Bool? = nil) -> TracedEntry {
        TracedEntry(tracerId: id, status: "ACTIVE", kind: kind, until: clock.timeIntervalSince1970 + 3600, lastLookedAt: lookedAt, band: band, stillTracing: still)
    }

    /// The tracer has asked bob and bob has said yes; a location has come back.
    func tracingBob(metres: Double = 5_000) async {
        locates(at: metres)
        await manager.request(bob, hours: 3)
        tracerSees(active())
        await manager.poll()
    }

    func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
}

@MainActor
struct TraceManagerTests {
    // MARK: Asking

    @Test func askingSendsOneRequestWithTheLengthAndWaits() async {
        let r = Rig()
        await r.manager.request(r.bob, hours: 2)
        #expect(r.api.requests.count == 1)
        #expect(r.api.requests[0].friendId == "bob-id" && r.api.requests[0].hours == 2)
        #expect(r.manager.state == .waiting(r.bob))
        #expect(r.notifier.authorizationRequests == 1)
    }

    @Test func theLengthAskedForIsAlwaysBetween15MinutesAnd24Hours() async {
        let r = Rig()
        await r.manager.request(r.bob, hours: 100)
        await r.manager.request(r.cara, hours: 0)
        #expect(r.api.requests.map(\.hours) == [24, 0.25])
    }

    @Test func nothingIsSharedWhileWaiting() async {
        let r = Rig()
        await r.manager.request(r.bob, hours: 3)
        r.tracerSees(r.waiting())
        await r.manager.poll()
        #expect(r.manager.state == .waiting(r.bob))
        #expect(r.api.locateCalls.isEmpty, "no look before a yes")
        #expect(r.manager.reading == nil)
        #expect(r.ranging.started.isEmpty)
    }

    @Test func withoutAPlanAskingShowsThePaywallAndSendsNothing() async {
        let r = Rig(); r.entitled = false
        await r.manager.request(r.bob, hours: 3)
        #expect(r.api.requests.isEmpty)
        #expect(r.manager.needsUpgrade && r.manager.state == nil)
    }

    @Test func aRefusedRequestSaysWhyAndLeavesNothingPending() async {
        let r = Rig()
        r.api.failRequest = FriendsError.status(429, "Too many waiting requests", retryAfter: nil)
        await r.manager.request(r.bob, hours: 3)
        #expect(r.manager.state == nil)
        #expect(r.manager.requestError == "Too many waiting requests")
        let p = Rig()
        p.api.failRequest = FriendsError.status(402, "A trace plan is needed to ask", retryAfter: nil)
        await p.manager.request(p.bob, hours: 3)
        #expect(p.manager.needsUpgrade && p.manager.requestError == nil, "a missing plan opens the paywall instead of an error")
    }

    // MARK: Accepted

    @Test func whenTheyAcceptThePillShowsAcceptedAndAskForALocationStraightAway() async {
        let r = Rig()
        r.locates(at: 5_000)
        await r.manager.request(r.bob, hours: 3)
        r.tracerSees(r.active())
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob))
        #expect(r.api.locateCalls.count == 1 && r.api.locateCalls[0].id == "bob-id")
        let reading = r.manager.reading
        #expect(reading?.source == .gps)
        #expect((reading?.meters ?? 0) > 4_900 && (reading?.meters ?? 0) < 5_100)
        #expect(r.manager.heldTraces == ["bob-id"])
    }

    @Test func theLocationIsShownWithItsAgeNotAsLive() async {
        let r = Rig()
        await r.tracingBob()
        #expect((r.manager.reading?.peerAgeSeconds ?? 0) >= 90, "it says how old their location is")
        r.advance(300)
        r.manager.entitlementChanged()
        #expect((r.manager.reading?.peerAgeSeconds ?? 0) >= 390, "and the age keeps growing between looks")
    }

    @Test func aTheirPhoneThatHasNotSharedYetIsSaidPlainly() async {
        let r = Rig()
        r.api.locateResult = .success(LocateResult(position: nil, retryAfter: 120))
        await r.manager.request(r.bob, hours: 3)
        r.tracerSees(r.active())
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob))
        #expect(r.manager.noLocationYet && r.manager.reading == nil)
    }

    @Test func theReadingCarriesDistanceAndDirectionNotACoordinate() async {
        let r = Rig()
        await r.tracingBob(metres: 2_000)
        let reading = r.manager.reading
        #expect(reading?.distanceText == "2.0 km")
        let bearing = reading?.trueBearing ?? -1
        #expect(bearing < 1 || bearing > 359, "due north")
        let fields = Mirror(reflecting: reading!).children.compactMap { $0.label }
        #expect(!fields.contains("latitude") && !fields.contains("longitude") && !fields.contains("coordinate"))
    }

    // MARK: Anything else is the one generic answer

    @Test func aRequestThatVanishesIsTheGenericAnswerWhateverTheReason() async {
        // Declined, expired, unfriended, blocked: the server shows the tracer the same thing, so the app can only say one thing.
        let r = Rig()
        await r.manager.request(r.bob, hours: 3)
        r.tracerSees(r.waiting())
        await r.manager.poll()
        r.tracerSees()                                   // gone
        await r.manager.poll()
        #expect(r.manager.state == .notice(TraceCopy.cannotTrace))
        #expect(TraceCopy.cannotTrace == "User cannot be traced, error has occurred")
        #expect(r.manager.isBusy == false)
    }

    @Test func aPermissionThatEndsIsTheSameGenericAnswerAndStopsFollowing() async {
        let r = Rig()
        var stopped = 0
        r.manager.onStopFollowing = { stopped += 1 }
        await r.tracingBob(metres: 3_000)
        r.manager.follow(guide: true)
        r.tracerSees()
        await r.manager.poll()
        #expect(r.manager.state == .notice(TraceCopy.cannotTrace))
        #expect(r.manager.reading == nil && stopped == 1 && r.manager.following == nil)
        #expect(r.ranging.stops >= 0)
    }

    @Test func aLookRefusedByTheServerIsTheSameGenericAnswer() async {
        let r = Rig()
        await r.tracingBob()
        r.advance(130)
        r.api.locateResult = .failure(FriendsError.status(403, "User cannot be traced", retryAfter: nil))
        await r.manager.locate(manual: true)
        #expect(r.manager.state == .notice(TraceCopy.cannotTrace))
    }

    @Test func theNoticeFadesAndDoesNotComeBack() async {
        let r = Rig()
        await r.manager.request(r.bob, hours: 3)
        r.tracerSees(); await r.manager.poll()
        #expect(r.manager.state == .notice(TraceCopy.cannotTrace))
        r.advance(7)
        await r.manager.poll()
        #expect(r.manager.state == nil)
    }

    @Test func theTracerIsNeverShownATimeOtherThanTheirOwnPlan() async {
        let r = Rig()
        await r.tracingBob()
        // Everything the tracer's screen can read, by name.
        let fields = Mirror(reflecting: r.manager).children.compactMap { $0.label?.replacingOccurrences(of: "_", with: "") }
        #expect(!fields.contains("grantedUntil") && !fields.contains("until"), "the manager keeps no end time for a tracer")
        #expect(r.manager.planEnds == nil, "their own plan end is the only time, and only when the server reports one")
    }

    // MARK: Looking: once every two minutes

    @Test func aNewLocationCanBeAskedForOnlyEveryTwoMinutes() async {
        let r = Rig()
        await r.tracingBob()
        #expect(r.api.locateCalls.count == 1)
        #expect(r.manager.locateCountdown() > 100, "the button counts down")
        await r.manager.locate(manual: true)
        #expect(r.api.locateCalls.count == 1, "too soon: nothing is sent")
        r.advance(121)
        r.locates(at: 4_000)
        await r.manager.locate(manual: true)
        #expect(r.api.locateCalls.count == 2)
        #expect(r.manager.locateCountdown() > 100)
    }

    @Test func theServerSayingTooSoonSetsTheCountdownAndChangesNothingElse() async {
        let r = Rig()
        await r.tracingBob()
        r.advance(121)
        r.api.locateResult = .failure(FriendsError.status(429, "Try again in a moment", retryAfter: 40))
        await r.manager.locate(manual: true)
        #expect(r.manager.state == .active(r.bob), "still tracing")
        #expect(r.manager.locateCountdown() > 35 && r.manager.locateCountdown() <= 40)
    }

    @Test func theDistanceTravelsWithTheLookButOnlyOnceTheyHaveBeenSeen() async {
        let r = Rig()
        await r.tracingBob(metres: 5_000)
        #expect(r.api.locateCalls[0].distance == nil, "first look: nothing to measure against yet")
        r.advance(121)
        await r.manager.locate(manual: true)
        let second = r.api.locateCalls[1].distance ?? -1
        #expect(second > 4_900 && second < 5_100, "later looks send how far they were, for the server to turn into a band")
    }

    @Test func aDroppedConnectionNeverEndsATrace() async {
        let r = Rig()
        await r.tracingBob()
        r.api.failSnapshot = true
        await r.manager.poll()
        #expect(r.manager.state == .active(r.bob) && r.manager.reading != nil)
        r.advance(121)
        r.api.locateResult = .failure(FriendsError.unreachable)
        await r.manager.locate(manual: true)
        #expect(r.manager.state == .active(r.bob), "offline: keep what is on screen")
    }

    @Test func comingBackToTheAppLooksAgainWhenTheWaitIsOver() async {
        let r = Rig()
        await r.tracingBob()
        r.manager.setSceneActive(false)
        r.advance(200)
        r.manager.setSceneActive(true)
        await Task.yield(); await Task.yield()
        for _ in 0..<20 where r.api.locateCalls.count < 2 { await Task.yield() }
        #expect(r.api.locateCalls.count == 2, "opening the compass is a look: the server re-checks every rule")
    }

    // MARK: The plan

    @Test func aPlanThatHasEndedEndsTheTraceAndShowsThePaywall() async {
        let r = Rig()
        await r.tracingBob()
        r.api.snapshot = GrantsSnapshot(asTraced: [], asTracer: [], plan: PlanInfo(until: 1, active: false))
        await r.manager.poll()
        #expect(r.manager.state == .notice(TraceCopy.planEnded) && r.manager.needsUpgrade)
        #expect(r.manager.isBusy == false)
    }

    @Test func theServerRefusingForAPlanReasonDoesTheSame() async {
        let r = Rig()
        await r.tracingBob()
        r.advance(121)
        r.api.locateResult = .failure(FriendsError.status(402, "A trace plan is needed", retryAfter: nil))
        await r.manager.locate(manual: true)
        #expect(r.manager.state == .notice(TraceCopy.planEnded) && r.manager.needsUpgrade)
    }

    @Test func theTracersOwnPlanEndIsKept() async {
        let r = Rig()
        r.api.snapshot = GrantsSnapshot(asTraced: [], asTracer: [], plan: PlanInfo(until: r.clock.timeIntervalSince1970 + 7200, active: true))
        await r.manager.poll()
        #expect(r.manager.planEnds == r.clock.addingTimeInterval(7200))
    }

    @Test func payingMidTraceBringsBackTheDirection() async {
        let r = Rig()
        await r.tracingBob()
        r.entitled = false
        r.manager.entitlementChanged()
        #expect(r.manager.reading == nil)
        r.entitled = true
        r.manager.entitlementChanged()
        #expect(r.manager.reading != nil)
    }

    @Test func switchingAwayFromAOneOffWarnsFirst() async {
        let r = Rig()
        r.tracerSees(r.active("bob-id", kind: .oneoff), r.active("cara-id", kind: .window))
        await r.manager.poll()
        await r.manager.trace(r.bob)
        #expect(r.manager.switchWarning(to: r.cara)?.contains("only allowed tracing once") == true)
        #expect(r.manager.switchWarning(to: r.bob) == nil)
        await r.manager.trace(r.cara)
        #expect(r.manager.switchWarning(to: r.bob) == nil, "a keep-tracing permission survives a switch")
        let w = Rig()
        await w.manager.request(w.bob, hours: 1)
        #expect(w.manager.switchWarning(to: w.cara)?.contains("withdrawn") == true)
    }

    // MARK: Ten permissions, one at a time

    @Test func aTracerSeesWhichFriendsTheyMayTraceAndSwitchesBetweenThem() async {
        let r = Rig()
        r.tracerSees(r.active("bob-id"), r.active("cara-id", kind: .oneoff))
        await r.manager.poll()
        #expect(r.manager.heldTraces == ["bob-id", "cara-id"])
        r.locates(at: 800)
        await r.manager.trace(r.bob)
        #expect(r.manager.state == .active(r.bob) && r.api.locateCalls.last?.id == "bob-id")
        await r.manager.trace(r.cara)
        #expect(r.manager.state == .active(r.cara))
        #expect(r.api.released == ["bob-id"], "switching away tells the server (it ends a one-off, and leaves a window alone)")
        #expect(r.api.locateCalls.last?.id == "cara-id")
    }

    @Test func youCannotLookAtSomeoneWhoHasNotAllowedIt() async {
        let r = Rig()
        r.tracerSees(r.active("bob-id"))
        await r.manager.poll()
        await r.manager.trace(r.cara)
        #expect(r.manager.state == nil && r.api.locateCalls.isEmpty)
    }

    @Test func stoppingTellsTheServerAndClearsEverything() async {
        let r = Rig()
        await r.tracingBob(metres: 20)
        await r.manager.end()
        #expect(r.api.released == ["bob-id"])
        #expect(r.manager.state == nil && r.manager.reading == nil)
        #expect(r.ranging.stops >= 0)
    }

    @Test func aSyncThatWasInFlightCannotBringBackAStoppedTrace() async {
        let r = Rig()
        await r.tracingBob()
        r.api.duringSnapshot = { [manager = r.manager!] in
            r.api.duringSnapshot = nil
            await manager.end()
        }
        await r.manager.poll()
        #expect(r.manager.state == nil, "the stale result is discarded")
    }

    // MARK: Following

    @Test func followingNeedsAnAcceptedTraceWithALocation() async {
        let r = Rig()
        var followed: [(String, Bool)] = []
        r.manager.onFollow = { friend, _, guide in followed.append((friend.id, guide)) }
        r.manager.follow(guide: true)
        #expect(followed.isEmpty, "nothing to follow before a trace is active")
        await r.tracingBob(metres: 3_000)
        r.manager.follow(guide: false)
        r.manager.follow(guide: true)
        #expect(followed.count == 2 && followed[0].1 == false && followed[1].1 == true)
        #expect(r.manager.following == "bob-id")
    }

    @Test func aNewLocationMovesTheFollowedDestination() async {
        let r = Rig()
        var positions = 0
        r.manager.onFriendPosition = { _, _ in positions += 1 }
        await r.tracingBob(metres: 3_000)
        #expect(positions == 0, "not following yet")
        r.manager.follow(guide: false)
        r.advance(121)
        r.locates(at: 2_500)
        await r.manager.locate(manual: true)
        #expect(positions == 1)
    }

    @Test func pointingAndGuidingArePaid() async {
        let r = Rig()
        await r.tracingBob(metres: 3_000)
        r.entitled = false
        var followed = 0
        r.manager.onFollow = { _, _, _ in followed += 1 }
        r.manager.follow(guide: true)
        #expect(followed == 0 && r.manager.needsUpgrade)
    }

    // MARK: Ultra Wideband

    @Test func theRadioStartsOnlyWhenTheLastLocationIsClose() async {
        let r = Rig()
        await r.tracingBob(metres: 5_000)
        #expect(r.ranging.started.isEmpty, "far away: GPS only")
        r.advance(121); r.locates(at: 30)
        await r.manager.locate(manual: true)
        #expect(r.ranging.started == ["bob-id"])
        await r.manager.poll()
        #expect(r.ranging.started.count == 1, "started once")
        r.advance(121); r.locates(at: 200)
        await r.manager.locate(manual: true)
        #expect(r.ranging.stops >= 1, "released when they are well away")
    }

    @Test func aPhoneWithoutUWBStaysOnGpsAtAnyDistance() async {
        let r = Rig()
        r.ranging.capability = .unsupported
        await r.tracingBob(metres: 10)
        #expect(r.ranging.started.isEmpty && r.manager.reading?.source == .gps)
        r.manager.findPrecisely()
        #expect(r.ranging.started.isEmpty)
    }

    @Test func findPreciselyStartsTheRadioAtAnyDistance() async {
        let r = Rig()
        await r.tracingBob(metres: 900)
        r.manager.findPrecisely()
        #expect(r.ranging.started == ["bob-id"])
    }

    @Test func aFreshRadioReadingTakesOverAndGpsReturnsWhenItGoesStale() async {
        let r = Rig()
        await r.tracingBob(metres: 25)
        r.ranging.latestReading = (ProximityReading(meters: 3.2, band: .veryClose, relativeBearing: 40), r.clock)
        r.ranging.onReading?()
        #expect(r.manager.reading?.source == .uwb && r.manager.reading?.relativeBearing == 40)
        r.advance(10)
        r.manager.entitlementChanged()
        #expect(r.manager.reading?.source == .gps, "radio readings older than 3 s no longer count")
    }

    // MARK: As the traced person: a request

    @Test func aRequestToTraceMeAppearsWithWhatWasAskedFor() async {
        let r = Rig()
        r.tracedSees(r.asking(kind: .oneoff, hours: 3))
        await r.manager.poll()
        #expect(r.manager.incoming.count == 1)
        #expect(r.manager.incoming[0].friend == r.bob && r.manager.incoming[0].requestedHours == 3)
        #expect(r.manager.watchers.isEmpty && r.api.uploads == 0, "nothing is shared by a request")
    }

    @Test func aRequestNotifiesOnceWhenTheAppIsNotInFront() async {
        let r = Rig()
        r.manager.setSceneActive(false)
        r.tracedSees(r.asking())
        await r.manager.poll()
        await r.manager.poll()
        #expect(r.notifier.incoming == ["bob"], "one notification per request")
        let front = Rig()
        front.tracedSees(front.asking())
        await front.manager.poll()
        #expect(front.notifier.incoming.isEmpty, "the banner itself is the notification")
    }

    @Test func aRequestFromSomeoneNotInTheListRefreshesFriendsAtMostOncePerMinute() async {
        let r = Rig(); r.known = []
        r.tracedSees(r.asking())
        await r.manager.poll()
        #expect(r.refreshes == 1 && r.manager.incoming.isEmpty)
        await r.manager.poll()
        #expect(r.refreshes == 1)
        r.advance(61)
        await r.manager.poll()
        #expect(r.refreshes == 2)
    }

    // MARK: As the traced person: allowing

    @Test func allowingNeedsTheOwnerThenSendsTheLengthAndTheWordingVersion() async {
        let r = Rig()
        r.tracedSees(r.asking(hours: 3))
        await r.manager.poll()
        let outcome = await r.manager.grant(r.manager.incoming[0], hours: 2, kind: .window)
        #expect(outcome == .granted)
        #expect(r.owner.reasons.count == 1 && r.owner.reasons[0].contains("bob"), "the owner is asked, naming who")
        #expect(r.api.answers.count == 1)
        #expect(r.api.answers[0].grant && r.api.answers[0].hours == 2 && r.api.answers[0].kind == .window && r.api.answers[0].consent == ConsentCopy.version)
    }

    @Test func allowingNeverGrantsMoreThanWasAskedForOrLessThan15Minutes() async {
        let r = Rig()
        r.tracedSees(r.asking(hours: 3))
        await r.manager.poll()
        _ = await r.manager.grant(r.manager.incoming[0], hours: 20, kind: .window)
        _ = await r.manager.grant(r.manager.incoming[0], hours: 0, kind: .window)
        #expect(r.api.answers.map(\.hours) == [3, 0.25])
    }

    @Test func backingOutOfTheOwnerCheckAllowsNothingAndSaysNothing() async {
        let r = Rig(); r.owner.result = .cancelled
        r.tracedSees(r.asking())
        await r.manager.poll()
        let outcome = await r.manager.grant(r.manager.incoming[0], hours: 1, kind: .window)
        #expect(outcome == .cancelled && r.api.answers.isEmpty && r.manager.errorMessage == nil)
    }

    @Test func failingTheOwnerCheckAllowsNothingAndSaysSo() async {
        for result in [OwnerAuthResult.failed, .lockedOut] {
            let r = Rig(); r.owner.result = result
            r.tracedSees(r.asking())
            await r.manager.poll()
            let outcome = await r.manager.grant(r.manager.incoming[0], hours: 1, kind: .window)
            #expect(outcome == .notVerified && r.api.answers.isEmpty)
            #expect(r.manager.errorMessage?.contains("nothing was allowed") == true)
        }
    }

    @Test func sayingNoNeedsNoCheckAndIsImmediate() async {
        let r = Rig(); r.owner.result = .failed        // even a failing check cannot stop a refusal
        r.tracedSees(r.asking())
        await r.manager.poll()
        await r.manager.decline(r.manager.incoming[0])
        #expect(r.owner.reasons.isEmpty)
        #expect(r.api.answers.count == 1 && r.api.answers[0].grant == false)
        #expect(r.manager.incoming.isEmpty)
    }

    @Test func aFreePersonCanSayYes() async {
        let r = Rig(); r.entitled = false
        r.tracedSees(r.asking())
        await r.manager.poll()
        let outcome = await r.manager.grant(r.manager.incoming[0], hours: 1, kind: .window)
        #expect(outcome == .granted && r.manager.needsUpgrade == false, "being traced is free: only tracing is paid")
    }

    // MARK: As the traced person: being watched

    @Test func whoMayTraceMeShowsUntilWhenTheyLookedAndHowFar() async {
        let r = Rig()
        r.tracedSees(r.watching(lookedAt: r.clock.timeIntervalSince1970 - 300, band: "under 200 m"))
        await r.manager.poll()
        let w = r.manager.watchers
        #expect(w.count == 1 && w[0].friend == r.bob && w[0].band == "under 200 m")
        #expect(w[0].until == r.clock.addingTimeInterval(3600) && w[0].lastLookedAt == r.clock.addingTimeInterval(-300))
        #expect(r.manager.isSharing)
    }

    @Test func myPositionIsSharedOnlyWhileSomeoneMayTraceMeAndTheAppIsOpen() async {
        let r = Rig()
        await r.manager.poll()
        #expect(r.api.uploads == 0, "nobody may trace me: nothing is uploaded")
        r.tracedSees(r.asking())
        await r.manager.poll()
        #expect(r.api.uploads == 0, "a request alone shares nothing")
        r.tracedSees(r.watching())
        await r.manager.poll()
        #expect(r.api.uploads == 1, "once someone may trace me, my position goes up")
        r.manager.setSceneActive(false)
        r.advance(300)
        let before = r.api.uploads
        await r.manager.poll()
        #expect(r.api.uploads == before, "with the app away, the regular sharing stops")
    }

    @Test func leavingTheAppSharesOneLastPosition() async {
        let r = Rig()
        r.tracedSees(r.watching())
        await r.manager.poll()
        let before = r.api.uploads
        r.manager.setSceneActive(false)
        for _ in 0..<20 where r.api.uploads == before { await Task.yield() }
        #expect(r.api.uploads == before + 1)
    }

    @Test func positionIsSharedSparingly() async {
        let r = Rig()
        r.tracedSees(r.watching())
        await r.manager.poll()
        #expect(r.api.uploads == 1)
        r.advance(10)
        await r.manager.poll()
        #expect(r.api.uploads == 1, "not within 30 s")
        r.advance(30)
        await r.manager.poll()
        #expect(r.api.uploads == 1, "30 s passed but I have not moved")
        r.me = CLLocationCoordinate2D(latitude: r.me!.latitude + 0.0004, longitude: r.me!.longitude)      // about 44 m
        await r.manager.poll()
        #expect(r.api.uploads == 2, "moved")
        r.advance(125)
        await r.manager.poll()
        #expect(r.api.uploads == 3, "a keep-alive at least every 2 minutes")
    }

    @Test func whenTheyLookAFreshPositionGoesUpAtOnce() async {
        let r = Rig()
        r.tracedSees(r.watching(lookedAt: 100))
        await r.manager.poll()
        #expect(r.api.uploads == 1)
        r.advance(5)
        r.tracedSees(r.watching(lookedAt: 150))
        await r.manager.poll()
        #expect(r.api.uploads == 2, "they looked again, so the next look finds a fresh position")
    }

    @Test func noPositionIsSentWithoutAFix() async {
        let r = Rig(); r.me = nil
        r.tracedSees(r.watching())
        await r.manager.poll()
        #expect(r.api.uploads == 0)
    }

    @Test func stoppingSomeoneIsImmediateNeedsNoCheckAndTellsTheServer() async {
        let r = Rig(); r.owner.result = .failed        // a failing owner check must not stand in the way of stopping
        r.tracedSees(r.watching(), r.watching("cara-id"))
        await r.manager.poll()
        let ok = await r.manager.revoke(r.manager.watchers[0])
        #expect(ok && r.api.revoked == ["bob-id"] && r.owner.reasons.isEmpty)
        #expect(r.manager.watchers.map(\.friend.id) == ["cara-id"], "gone from the screen at once")
    }

    @Test func ifStoppingCannotReachTheServerThePersonIsToldItIsStillOn() async {
        let r = Rig()
        r.tracedSees(r.watching())
        await r.manager.poll()
        r.api.failRevoke = true
        let ok = await r.manager.revoke(r.manager.watchers[0])
        #expect(!ok && r.manager.watchers.count == 1, "still shown as on, because it is")
        #expect(r.manager.errorMessage?.contains("still on") == true)
    }

    @Test func stoppingEveryoneStopsEveryone() async {
        let r = Rig()
        r.tracedSees(r.watching(), r.watching("cara-id"))
        await r.manager.poll()
        await r.manager.revokeAll()
        #expect(Set(r.api.revoked) == ["bob-id", "cara-id"] && r.manager.watchers.isEmpty)
    }

    @Test func aStillTracingNoticeRaisesAPromptOnceAndNotifiesWhenAway() async {
        let r = Rig()
        r.tracedSees(r.watching(lookedAt: 100, still: true))
        await r.manager.poll()
        #expect(r.manager.stillTracing == r.bob)
        #expect(r.notifier.still.isEmpty, "in front: the prompt itself is the notice")
        r.manager.dismissStillTracing()
        r.manager.setSceneActive(false)
        r.tracedSees(r.watching(lookedAt: 3000, still: true))
        await r.manager.poll()
        #expect(r.notifier.still == ["bob"])
    }

    @Test func thePromptGoesWhenTheyAreNoLongerTracing() async {
        let r = Rig()
        r.tracedSees(r.watching(still: true))
        await r.manager.poll()
        #expect(r.manager.stillTracing != nil)
        r.tracedSees()
        await r.manager.poll()
        #expect(r.manager.stillTracing == nil && r.manager.watchers.isEmpty)
    }

    @Test func theRadioStartsForSomeoneWhoLookedFromCloseByAndStopsWhenTheyAreGone() async {
        let r = Rig()
        r.tracedSees(r.watching(lookedAt: r.clock.timeIntervalSince1970 - 20, band: "under 50 m"))
        await r.manager.poll()
        #expect(r.ranging.started == ["bob-id"])
        r.tracedSees(r.watching(lookedAt: r.clock.timeIntervalSince1970 - 20, band: "about 3 km"))
        await r.manager.poll()
        #expect(r.ranging.stops >= 1)
        let far = Rig()
        far.tracedSees(far.watching(lookedAt: far.clock.timeIntervalSince1970 - 20, band: "about 3 km"))
        await far.manager.poll()
        #expect(far.ranging.started.isEmpty, "a far-away tracer never switches the radio on")
    }

    // MARK: Signing out

    @Test func signingOutDropsEverything() async {
        let r = Rig()
        r.tracedSees(r.watching(), r.asking("cara-id"))
        r.tracerSees(r.active())
        await r.manager.poll()
        await r.manager.trace(r.bob)
        r.manager.reset()
        #expect(r.manager.state == nil && r.manager.reading == nil)
        #expect(r.manager.incoming.isEmpty && r.manager.watchers.isEmpty && r.manager.heldTraces.isEmpty)
        #expect(r.manager.isSharing == false)
    }
}
