//
//  PlanStoreTests.swift
//  ThatWayTests
//
//  Buying a plan: the phone never decides what a plan is. It hands Apple's signed purchase to the server and applies the
//  answer; a purchase is only "finished" with Apple once the server has recorded it, so a failure is retried and never lost.
//

import Testing
import Foundation
@testable import ThatWay

@MainActor
private final class FakeBilling: PlanBilling {
    var shown: [PlanOffer] = [PlanOffer(plan: .trace3, price: "$0.99"), PlanOffer(plan: .lifetrace, price: "$499.00")]
    var failOffers = false
    var outcome: PurchaseOutcome = .cancelled
    var failPurchase = false
    var current: [SignedPurchase] = []
    var finished: [String] = []
    let stream = AsyncStream<SignedPurchase>.makeStream()

    func signed(_ jws: String) -> SignedPurchase { SignedPurchase(jws: jws, finish: { [unowned self] in finished.append(jws) }) }
    func offers() async throws -> [PlanOffer] { if failOffers { throw FriendsError.unreachable }; return shown }
    func purchase(_ plan: PlanProduct) async throws -> PurchaseOutcome { if failPurchase { throw FriendsError.unreachable }; return outcome }
    func currentPurchases() async -> [SignedPurchase] { current }
    func updates() -> AsyncStream<SignedPurchase> { stream.stream }
}

@MainActor
private final class FakePlanAPI: PlanAPI {
    var status = PlanStatus(until: nil, forever: false, results: nil)
    var fail = false
    var sent: [[String]] = []
    func planStatus() async throws -> PlanStatus { if fail { throw FriendsError.unreachable }; return status }
    func syncPlan(transactions: [String]) async throws -> PlanStatus { if fail { throw FriendsError.unreachable }; sent.append(transactions); return status }
}

@MainActor
struct PlanStoreTests {
    private func make() -> (PlanStore, FakeBilling, FakePlanAPI, () -> [PlanStatus]) {
        let billing = FakeBilling(), api = FakePlanAPI()
        let store = PlanStore(billing: billing, api: api)
        var applied: [PlanStatus] = []
        store.onStatus = { applied.append($0) }
        return (store, billing, api, { applied })
    }

    @Test func offersAreShownWithTheStoresOwnPrices() async {
        let (store, _, _, _) = make()
        #expect(store.loaded == false)
        await store.loadOffers()
        #expect(store.loaded && store.offers.map(\.price) == ["$0.99", "$499.00"])
    }

    @Test func offersThatCannotLoadSayNothingIsForSale() async {
        let (store, billing, _, _) = make()
        billing.failOffers = true
        await store.loadOffers()
        #expect(store.loaded && store.offers.isEmpty && store.message != nil)
    }

    @Test func aPurchaseGoesToTheServerAndTheServersAnswerIsApplied() async {
        let (store, billing, api, applied) = make()
        billing.outcome = .purchased(billing.signed("jws-1"))
        api.status = PlanStatus(until: 1_800_010_800, forever: false, results: [PlanSyncResult(ok: true, reason: nil)])
        await store.buy(.trace3)
        #expect(api.sent == [["jws-1"]])
        #expect(applied() == [api.status])
        #expect(billing.finished == ["jws-1"], "finished with Apple only after the server recorded it")
        #expect(store.message == "Your plan is active.")
    }

    @Test func ifTheServerCannotBeReachedThePurchaseIsNotFinishedAndNotLost() async {
        let (store, billing, api, applied) = make()
        billing.outcome = .purchased(billing.signed("jws-1"))
        api.fail = true
        await store.buy(.trace3)
        #expect(billing.finished.isEmpty && applied().isEmpty)
        #expect(store.message?.contains("safe with Apple") == true)
    }

    @Test func aPurchaseTheServerRefusesIsExplainedAndNotCredited() async {
        let (store, billing, api, _) = make()
        billing.outcome = .purchased(billing.signed("jws-1"))
        api.status = PlanStatus(until: nil, forever: false, results: [PlanSyncResult(ok: false, reason: "belongs to another account")])
        await store.buy(.lifetrace)
        #expect(store.message?.contains("another ThatWay account") == true)
        #expect(billing.finished.isEmpty)
        api.status = PlanStatus(until: nil, forever: false, results: [PlanSyncResult(ok: false, reason: "not verified")])
        await store.buy(.lifetrace)
        #expect(store.message?.contains("couldn’t confirm") == true)
    }

    @Test func cancellingChangesNothing() async {
        let (store, billing, api, _) = make()
        billing.outcome = .cancelled
        await store.buy(.trace3)
        #expect(api.sent.isEmpty && store.message == nil && store.isWorking == false)
    }

    @Test func aPendingPurchaseSaysItIsWaiting() async {
        let (store, billing, api, _) = make()
        billing.outcome = .pending
        await store.buy(.trace3)
        #expect(api.sent.isEmpty && store.message?.contains("Waiting for approval") == true)
    }

    @Test func aFailedPurchaseSaysSoPlainlyAndPointsToRestore() async {
        let (store, billing, _, _) = make()
        billing.failPurchase = true
        await store.buy(.trace3)
        #expect(store.message?.contains("Restore") == true)
    }

    @Test func restoreHandsApplesCurrentPurchasesToTheServer() async {
        let (store, billing, api, applied) = make()
        billing.current = [billing.signed("sub"), billing.signed("life")]
        api.status = PlanStatus(until: nil, forever: true, results: [PlanSyncResult(ok: true, reason: nil), PlanSyncResult(ok: true, reason: nil)])
        await store.restore()
        #expect(api.sent == [["sub", "life"]] && applied().first?.forever == true)
    }

    @Test func restoringWithNothingSaysWhy() async {
        let (store, _, api, _) = make()
        await store.restore()
        #expect(api.sent.isEmpty && store.message?.contains("Nothing to restore") == true)
    }

    @Test func aPurchaseThatArrivesOnItsOwnIsSettled() async {
        let (store, billing, api, applied) = make()
        api.status = PlanStatus(until: 1_800_100_000, forever: false, results: [PlanSyncResult(ok: true, reason: nil)])
        store.start()
        billing.stream.continuation.yield(billing.signed("renewal"))
        for _ in 0..<50 where api.sent.isEmpty { await Task.yield() }
        for _ in 0..<50 where billing.finished.isEmpty { await Task.yield() }
        store.stop()
        #expect(api.sent == [["renewal"]] && billing.finished == ["renewal"] && !applied().isEmpty)
    }

    @Test func refreshingAppliesTheServersStatus() async {
        let (store, _, api, applied) = make()
        api.status = PlanStatus(until: 1_800_100_000, forever: false, results: nil)
        await store.refresh()
        #expect(applied() == [api.status])
    }

    @Test func theFourPlansHaveTheNamesAndIdsTheServerKnows() {
        #expect(PlanProduct.allCases.map(\.title) == ["trace3", "trace24", "trace+", "lifetrace"])
        #expect(PlanProduct.allCases.map(\.rawValue) == ["com.thatway.trace3", "com.thatway.trace24", "com.thatway.traceplus", "com.thatway.lifetrace"])
    }
}

@MainActor
struct ServerPlanAppliedTests {
    private func fresh() -> UserDefaults { UserDefaults(suiteName: "plan-tests-\(UUID().uuidString)")! }

    @Test func aVerifiedPlanTurnsTracingOnWithItsEndTime() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlements(defaults: fresh(), now: { clock })
        e.applyServerPlan(until: clock.addingTimeInterval(3 * 3600).timeIntervalSince1970, forever: false)
        #expect(e.canTraceFriends && e.planEnds == clock.addingTimeInterval(3 * 3600))
    }

    @Test func aLifetimePlanHasNoEnd() {
        let e = Entitlements(defaults: fresh())
        e.applyServerPlan(until: 4_102_444_800, forever: true)
        #expect(e.canTraceFriends && e.planEnds == nil)
    }

    @Test func anEmptyAnswerDoesNotWipeATestUnlockWhileTheServerIsNotAuthoritative() {
        let e = Entitlements(defaults: fresh())
        e.unlockForTesting()
        e.applyServerPlan(until: nil, forever: false)
        #expect(!Entitlements.serverIsAuthoritative && e.canTraceFriends)
    }

    @Test func anOldPlanTheServerStillReportsGrantsNothing() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let e = Entitlements(defaults: fresh(), now: { clock })
        e.applyServerPlan(until: clock.addingTimeInterval(-60).timeIntervalSince1970, forever: false)
        #expect(!e.canTraceFriends)
    }
}
