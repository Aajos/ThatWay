//
//  EntitlementsTests.swift
//  ThatWayTests
//
//  The single paid switch: friend tracing needs payment, adding friends does not, the dummy purchase persists, and a timed
//  plan ends: tracing stops with it, and a reminder is scheduled for 30 minutes before.
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

    // MARK: A plan that ends

    @MainActor
    private final class FakeReminder: PlanReminding {
        var scheduled: [Date] = []
        var cancels = 0
        func schedule(endsAt: Date) { scheduled.append(endsAt) }
        func cancel() { cancels += 1 }
    }

    @Test func aTimedPassEndsAndTracingEndsWithIt() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlements(defaults: fresh(), now: { clock })
        e.unlockForTesting(hours: 3)
        #expect(e.canTraceFriends && e.planEnds == clock.addingTimeInterval(3 * 3600))
        clock = clock.addingTimeInterval(3 * 3600 - 1)
        #expect(e.canTraceFriends && e.planHasEnded == false)
        clock = clock.addingTimeInterval(2)
        #expect(!e.canTraceFriends && e.planHasEnded, "the moment the pass is over, so is tracing")
        #expect(e.timeLeft() == 0)
    }

    @Test func aPlanWithNoEndNeverEnds() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlements(defaults: fresh(), now: { clock })
        e.unlockForTesting()
        clock = clock.addingTimeInterval(10 * 365 * 86400)
        #expect(e.canTraceFriends && e.planEnds == nil && e.timeLeft() == nil)
    }

    @Test func buyingAgainStacksOnWhatIsLeft() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlements(defaults: fresh(), now: { clock })
        e.unlockForTesting(hours: 3); e.unlockForTesting(hours: 3)
        #expect(e.planEnds == clock.addingTimeInterval(6 * 3600), "a second pass adds to the first")
    }

    @Test func aTimedPlanSurvivesARelaunch() {
        let d = fresh()
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        Entitlements(defaults: d, now: { clock }).unlockForTesting(hours: 24)
        let again = Entitlements(defaults: d, now: { clock })
        #expect(again.canTraceFriends && again.planEnds == clock.addingTimeInterval(24 * 3600))
    }

    @Test func aReminderIsScheduledHalfAnHourBeforeTheEnd() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = FakeReminder()
        let e = Entitlements(defaults: fresh(), reminder: reminder, now: { clock })
        e.unlockForTesting(hours: 3)
        #expect(reminder.scheduled == [clock.addingTimeInterval(3 * 3600)], "the reminder is told when the plan ends; it fires 30 minutes earlier")
        #expect(LocalPlanReminder.lead == 30 * 60)
        e.lockForTesting()
        #expect(reminder.cancels >= 1)
    }

    @Test func aPlanWithNoEndSchedulesNoReminder() {
        let reminder = FakeReminder()
        Entitlements(defaults: fresh(), reminder: reminder).unlockForTesting()
        #expect(reminder.scheduled.isEmpty)
    }
}
