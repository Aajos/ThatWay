//
//  PlanStore.swift
//  ThatWay
//
//  Buying a trace plan. StoreKit 2 does the purchase; then the phone sends Apple's SIGNED transaction to the server, which
//  checks Apple's signature, works out how long the plan lasts and records it (backend/lambda/plan). The phone believes the
//  server's answer, not its own: a plan is whatever the server says it is, so a modified app gains nothing.
//
//    trace3      3-hour pass      consumable, stacks
//    trace24     24-hour pass     consumable, stacks
//    trace+      monthly          auto-renewing subscription
//    lifetrace   lifetime         non-consumable
//
//  Purchases are processed by Apple: refunds, subscriptions and receipts are Apple's. The words around the buttons say so.
//  The product ids below must match App Store Connect exactly (see ThatWay/Plans.storekit for local testing).
//
//  StoreKit and the server sit behind protocols, so every branch is tested without either.
//

import Foundation
import StoreKit
import Combine

enum PlanProduct: String, CaseIterable, Identifiable {
    case trace3 = "com.thatway.trace3"
    case trace24 = "com.thatway.trace24"
    case tracePlus = "com.thatway.traceplus"
    case lifetrace = "com.thatway.lifetrace"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trace3: return "trace3"
        case .trace24: return "trace24"
        case .tracePlus: return "trace+"
        case .lifetrace: return "lifetrace"
        }
    }

    var detail: String {
        switch self {
        case .trace3: return "3 hours of tracing. Buy again to add more time."
        case .trace24: return "24 hours of tracing. Buy again to add more time."
        case .tracePlus: return "Monthly. Renews automatically until you cancel it in your Apple ID settings."
        case .lifetrace: return "Pay once. Tracing for as long as ThatWay exists."
        }
    }
}

struct PlanOffer: Identifiable, Equatable {
    let plan: PlanProduct
    /// Already formatted for the person's store ("$0.99"), straight from Apple.
    let price: String
    var id: String { plan.id }
}

/// What the server says the plan is.
struct PlanStatus: Decodable, Equatable {
    /// When the plan ends (epoch seconds); nil when there is none.
    let until: Double?
    let forever: Bool
    var results: [PlanSyncResult]?
}

struct PlanSyncResult: Decodable, Equatable {
    let ok: Bool
    let reason: String?
}

/// A signed transaction from Apple, plus the way to tell StoreKit we have dealt with it.
struct SignedPurchase {
    let jws: String
    let finish: () async -> Void
}

enum PurchaseOutcome {
    case purchased(SignedPurchase)
    case cancelled
    /// Waiting for approval (Ask to Buy / a bank check): nothing to do until Apple reports it.
    case pending
}

@MainActor
protocol PlanBilling: AnyObject {
    func offers() async throws -> [PlanOffer]
    func purchase(_ plan: PlanProduct) async throws -> PurchaseOutcome
    /// The signed transactions Apple still counts for this Apple ID (subscriptions and lifetime), for "restore".
    func currentPurchases() async -> [SignedPurchase]
    /// Purchases that arrive on their own: renewals, an Ask to Buy approval, a refund.
    func updates() -> AsyncStream<SignedPurchase>
}

@MainActor
protocol PlanAPI: AnyObject {
    func planStatus() async throws -> PlanStatus
    func syncPlan(transactions: [String]) async throws -> PlanStatus
}

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var offers: [PlanOffer] = []
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    /// False until the offers have been asked for at least once (so the screen can say "loading" and not "unavailable").
    @Published private(set) var loaded = false

    /// The server's answer, applied to the entitlement (wired by AppModel).
    var onStatus: ((PlanStatus) -> Void)?

    private let billing: PlanBilling
    private let api: PlanAPI
    private var listener: Task<Void, Never>?

    init(billing: PlanBilling, api: PlanAPI) { self.billing = billing; self.api = api }

    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            guard let stream = self?.billing.updates() else { return }
            for await purchase in stream { await self?.settle([purchase]) }
        }
        Task { await refresh() }
    }

    func stop() { listener?.cancel(); listener = nil }

    /// What the server says now (on sign-in, and whenever the app comes to the front).
    func refresh() async {
        if let status = try? await api.planStatus() { onStatus?(status) }
    }

    func loadOffers() async {
        defer { loaded = true }
        do { offers = try await billing.offers() } catch { offers = []; message = "Plans can’t be shown right now. Check your connection." }
    }

    func buy(_ plan: PlanProduct) async {
        guard !isWorking else { return }
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            switch try await billing.purchase(plan) {
            case .purchased(let purchase): await settle([purchase])
            case .cancelled: break
            case .pending: message = "Waiting for approval. Your plan starts as soon as it is approved."
            }
        } catch {
            message = "The purchase didn’t go through, and you haven’t been charged for it by us. If Apple charged you, it will appear here shortly: tap Restore."
        }
    }

    /// "Restore purchases": hand Apple's current transactions to the server again.
    func restore() async {
        guard !isWorking else { return }
        isWorking = true; message = nil
        defer { isWorking = false }
        let purchases = await billing.currentPurchases()
        if purchases.isEmpty { message = "Nothing to restore. Passes are used up as time passes, so only a subscription or lifetrace can come back."; return }
        await settle(purchases)
    }

    /// Sends signed transactions to the server; only when it accepts them are they finished (so a failure is retried, not lost).
    private func settle(_ purchases: [SignedPurchase]) async {
        do {
            let status = try await api.syncPlan(transactions: purchases.map(\.jws))
            onStatus?(status)
            let accepted = status.results ?? []
            for (i, purchase) in purchases.enumerated() where i >= accepted.count || accepted[i].ok || accepted[i].reason == "refunded" {
                await purchase.finish()
            }
            if let bad = accepted.first(where: { !$0.ok }) {
                message = bad.reason == "belongs to another account" ? "That purchase already belongs to another ThatWay account." : "We couldn’t confirm that purchase with Apple yet."
            } else {
                message = "Your plan is active."
            }
        } catch {
            message = "We couldn’t reach ThatWay to record your purchase. It is safe with Apple: it will be recorded next time you open the app, or tap Restore."
        }
    }
}

// MARK: - The server

extension FriendsManager: PlanAPI {
    func planStatus() async throws -> PlanStatus { try await request(method: "GET", path: "/plan") }

    func syncPlan(transactions: [String]) async throws -> PlanStatus {
        try await request(method: "POST", path: "/plan/sync", body: ["transactions": transactions])
    }
}

// MARK: - StoreKit 2

@MainActor
final class StoreKitBilling: PlanBilling {
    private var products: [String: Product] = [:]

    func offers() async throws -> [PlanOffer] {
        let found = try await Product.products(for: PlanProduct.allCases.map(\.rawValue))
        products = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return PlanProduct.allCases.compactMap { plan in products[plan.rawValue].map { PlanOffer(plan: plan, price: $0.displayPrice) } }
    }

    func purchase(_ plan: PlanProduct) async throws -> PurchaseOutcome {
        if products[plan.rawValue] == nil { _ = try await offers() }
        guard let product = products[plan.rawValue] else { throw PlanError.unavailable }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PlanError.unverified }     // StoreKit's own check first
            return .purchased(SignedPurchase(jws: verification.jwsRepresentation, finish: { await transaction.finish() }))
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .cancelled
        }
    }

    func currentPurchases() async -> [SignedPurchase] {
        var found: [SignedPurchase] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                found.append(SignedPurchase(jws: result.jwsRepresentation, finish: { await transaction.finish() }))
            }
        }
        return found
    }

    func updates() -> AsyncStream<SignedPurchase> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        continuation.yield(SignedPurchase(jws: result.jwsRepresentation, finish: { await transaction.finish() }))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum PlanError: Error { case unavailable, unverified }
}
