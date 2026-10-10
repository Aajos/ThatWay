//
//  NearbyManagerTests.swift
//  ThatWayTests
//
//  The token exchange and the state machine, with a fake backend and a fake Ultra Wideband session (the real one needs
//  two UWB phones). What matters: nothing starts on a phone that cannot range, our token is published, ranging begins
//  only when the friend's token appears, and ending always cleans up and tells the watch.
//

import Testing
import Foundation
@testable import ThatWay
import ThatWayCore

@MainActor
private final class FakeAPI: NearbyOfferAPI {
    var published: [(friendId: String, token: String, kind: NearbyKind)] = []
    var available: [NearbyOffer] = []
    var ended: [String] = []
    var failOffers = false

    func putOffer(friendId: String, token: String, kind: NearbyKind) async { published.append((friendId, token, kind)) }
    func offers() async throws -> [NearbyOffer] {
        if failOffers { throw FriendsError.unreachable }
        return available
    }
    func endOffers(friendId: String) async { ended.append(friendId) }
}

@MainActor
private final class FakeSession: ProximitySession {
    var onUpdate: ((Double, Double?) -> Void)?
    var onEnded: (() -> Void)?
    var ranToken: String?
    var stopped = false
    func localToken() -> String? { "TUJD" }
    func run(peerToken: String) -> Bool { ranToken = peerToken; return true }
    func stop() { stopped = true }
}

@MainActor
struct NearbyManagerTests {
    private let friend = Friend(id: "bob-id", username: "bob", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)

    /// Waits (up to 3 s) for the poll loop to reach a condition, so the tests don't depend on how busy the machine is.
    private func eventually(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(40)) }

    private func make(capability: NearbyCapability = .uwbWithDirection, configured: Bool = true) -> (NearbyManager, FakeAPI, FakeSession) {
        let api = FakeAPI(), session = FakeSession()
        let manager = NearbyManager(api: api, capability: { capability }, isConfigured: { configured }, makeSession: { session }, pollInterval: .milliseconds(2))
        return (manager, api, session)
    }

    @Test func aPhoneWithoutUWBNeverTouchesTheBackend() async {
        let (manager, api, _) = make(capability: .unsupported)
        manager.start(with: friend)
        await settle()
        #expect(manager.state == .unsupported)
        #expect(api.published.isEmpty)
        manager.stop()
    }

    @Test func publishesOurTokenThenWaitsForTheFriend() async {
        let (manager, api, session) = make()
        manager.start(with: friend)
        await eventually(manager.state == .waiting)
        #expect(api.published.first?.friendId == "bob-id")
        #expect(api.published.first?.token == "TUJD")
        #expect(api.published.first?.kind == .uwb)
        #expect(manager.state == .waiting)
        #expect(session.ranToken == nil)
        manager.stop()
    }

    @Test func startsRangingWhenTheFriendsTokenAppears() async {
        let (manager, api, session) = make()
        var watchStates: [ProximityWatchState?] = []
        manager.onWatchState = { watchStates.append($0) }
        manager.start(with: friend)
        await eventually(manager.state == .waiting)
        api.available = [NearbyOffer(friendId: "bob-id", token: "QkJC", kind: .uwb, expiresAt: 9_999_999_999)]
        await eventually(session.ranToken != nil)
        #expect(session.ranToken == "QkJC")

        session.onUpdate?(12.4, 20)
        guard case .ranging(let reading) = manager.state else { Issue.record("not ranging: \(manager.state)"); return }
        #expect(abs(reading.meters - 12.4) < 0.01)
        #expect(reading.relativeBearing == 20)
        #expect(watchStates.last??.friendName == "bob")
        manager.stop()
    }

    @Test func anotherFriendsOfferIsIgnored() async {
        let (manager, api, session) = make()
        api.available = [NearbyOffer(friendId: "someone-else", token: "WFla", kind: .uwb, expiresAt: 9_999_999_999)]
        manager.start(with: friend)
        await eventually(manager.state == .waiting)
        await settle()
        #expect(session.ranToken == nil)
        #expect(manager.state == .waiting)
        manager.stop()
    }

    @Test func stoppingCleansUpAndTellsTheWatch() async {
        let (manager, api, session) = make()
        var watchStates: [ProximityWatchState?] = []
        manager.onWatchState = { watchStates.append($0) }
        manager.start(with: friend)
        await eventually(manager.state == .waiting)
        manager.stop()
        await eventually(!api.ended.isEmpty)
        #expect(session.stopped)
        #expect(api.ended == ["bob-id"])
        #expect(manager.state == .idle)
        #expect(watchStates.last == .some(nil), "the watch is told the session ended")
    }

    @Test func theFriendLeavingEndsTheSession() async {
        let (manager, api, session) = make()
        api.available = [NearbyOffer(friendId: "bob-id", token: "QkJC", kind: .uwb, expiresAt: 9_999_999_999)]
        manager.start(with: friend)
        await eventually(session.ranToken != nil)
        session.onEnded?()
        #expect(manager.state == .lost)
        await eventually(!api.ended.isEmpty)
        #expect(api.ended == ["bob-id"])
    }

    @Test func repeatedBackendFailuresSurfaceAsAMessage() async {
        let (manager, api, _) = make()
        api.failOffers = true
        manager.start(with: friend)
        await eventually({ if case .failed = manager.state { return true } else { return false } }())
        if case .failed = manager.state {} else { Issue.record("expected failed, got \(manager.state)") }
        manager.stop()
    }

    @Test func withoutTheServiceAddressItSaysSoInsteadOfRetrying() {
        let (manager, api, _) = make(configured: false)
        manager.start(with: friend)
        if case .failed(let message) = manager.state { #expect(message.contains("aren't switched on")) } else { Issue.record("expected failed") }
        #expect(api.published.isEmpty)
    }
}
