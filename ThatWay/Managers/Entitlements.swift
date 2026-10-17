//
//  Entitlements.swift
//  ThatWay
//
//  The ONE place that decides what is paid. Everything paid asks `canTraceFriends` (or a sibling added later); nothing else
//  knows how someone paid. Today the "payment" is a dummy: unlocking just sets a saved flag so the paywall flow can be built
//  and tested. When the real purchase exists (StoreKit, see the Apple Developer note) only `isPaid` changes.
//
//  Adding friends stays free. Tracing a friend, pointing the compass at one and guiding to one are the paid part.
//

import Foundation
import Combine

@MainActor
final class Entitlements: ObservableObject {
    /// Flip to `false` to make friend tracing free for everyone (the single switch).
    static let friendTracingRequiresPayment = true

    @Published private(set) var isPaid: Bool
    private let defaults: UserDefaults
    private let key = "entitlement.paid.dummy"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPaid = defaults.bool(forKey: key)
    }

    /// May this person trace, point to or guide to a friend?
    var canTraceFriends: Bool { !Self.friendTracingRequiresPayment || isPaid }

    /// Dummy purchase for now: no money moves. Replaced by the StoreKit purchase and restore.
    func unlockForTesting() { isPaid = true; defaults.set(true, forKey: key) }
    func lockForTesting() { isPaid = false; defaults.set(false, forKey: key) }
}
