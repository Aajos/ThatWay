//
//  EntitlementsTests.swift
//  ThatWayTests
//
//  The single paid switch: friend tracing needs payment, adding friends does not, and the dummy purchase persists.
//

import Testing
import Foundation
@testable import ThatWay

@MainActor
struct EntitlementsTests {
    private func fresh() -> UserDefaults {
        let d = UserDefaults(suiteName: "entitlements-tests-\(UUID().uuidString)")!
        return d
    }

    @Test func tracingFriendsIsPaid() {
        #expect(Entitlements.friendTracingRequiresPayment, "the switch is on: tracing is a paid feature")
        let e = Entitlements(defaults: fresh())
        #expect(e.isPaid == false)
        #expect(e.canTraceFriends == false)
    }

    @Test func theDummyUnlockTurnsItOnAndIsRemembered() {
        let d = fresh()
        let e = Entitlements(defaults: d)
        e.unlockForTesting()
        #expect(e.canTraceFriends)
        #expect(Entitlements(defaults: d).canTraceFriends, "still unlocked after a relaunch")
        e.lockForTesting()
        #expect(Entitlements(defaults: d).canTraceFriends == false)
    }
}
