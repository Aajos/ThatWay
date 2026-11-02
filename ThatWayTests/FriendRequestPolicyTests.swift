//
//  FriendRequestPolicyTests.swift
//  ThatWayTests
//
//  "Friends" setting: auto accept or requests only. It is remembered, defaults to the safe choice, and auto accept
//  tries each request once.
//

import Testing
import Foundation
@testable import ThatWay

struct FriendRequestPolicyTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "policy-tests-\(UUID().uuidString)")! }
    private func req(_ id: String) -> Friend { Friend(id: id, username: id, status: "INCOMING", requestedAt: nil, acceptedAt: nil) }

    @Test func theDefaultIsRequestsOnly() {
        #expect(FriendRequestPolicy.load(defaults()) == .requestsOnly)
    }

    @Test func theChoiceIsRemembered() {
        let d = defaults()
        FriendRequestPolicy.autoAccept.save(d)
        #expect(FriendRequestPolicy.load(d) == .autoAccept)
    }

    @Test func requestsOnlyNeverAcceptsOnItsOwn() {
        #expect(FriendRequestPolicy.requestsOnly.idsToAutoAccept(incoming: [req("a"), req("b")], alreadyTried: []).isEmpty)
    }

    @Test func autoAcceptTakesEachRequestOnce() {
        let p = FriendRequestPolicy.autoAccept
        #expect(p.idsToAutoAccept(incoming: [req("a"), req("b")], alreadyTried: []) == ["a", "b"])
        #expect(p.idsToAutoAccept(incoming: [req("a"), req("b"), req("c")], alreadyTried: ["a", "b"]) == ["c"])
        #expect(p.idsToAutoAccept(incoming: [], alreadyTried: []).isEmpty)
    }

    @Test func theTabIsCalledBuy() {
        #expect(AppScreen.store.label == "BUY")
    }
}
