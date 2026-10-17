//
//  Entitlements.swift
//  ThatWay
//
//  The ONE place that decides what is paid. Everything paid asks `canTraceFriends` (or a sibling added later); nothing else
//  knows how someone paid. Today the "payment" is a dummy: unlocking just sets a saved flag (and, for a timed pass, an end
//  time) so the paywall flow can be built and tested. When the real purchase exists (StoreKit, see the Apple Developer note)
//  only `isPaid` and `planEnds` change.
//
//  A plan can have an end (a 3-hour or 24-hour pass, a month) or none (the lifetime plan). When it ends, tracing ends with it,
//  on the phone and on the server. A reminder is scheduled for 30 minutes before the end.
//
//  Adding friends stays free. Saying yes to a trace request stays free. Tracing a friend, pointing the compass at one and
//  guiding to one are the paid part.
//

import Foundation
import Combine

@MainActor
final class Entitlements: ObservableObject {
    /// Flip to `false` to make friend tracing free for everyone (the single switch).
    static let friendTracingRequiresPayment = true

    @Published private(set) var isPaid: Bool
    /// When the current plan ends; nil for a plan that does not end (and while nothing is bought).
    @Published private(set) var planEnds: Date?

    private let defaults: UserDefaults
    private let reminder: PlanReminding?
    private let now: () -> Date
    private let key = "entitlement.paid.dummy"
    private let endKey = "entitlement.planEnds.dummy"

    init(defaults: UserDefaults = .standard, reminder: PlanReminding? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.reminder = reminder; self.now = now
        isPaid = defaults.bool(forKey: key)
        let end = defaults.double(forKey: endKey)
        planEnds = end > 0 ? Date(timeIntervalSince1970: end) : nil
        syncReminder()
    }

    /// Has a plan that did end (the flag is still saved, but the time is over).
    var planHasEnded: Bool { isPaid && (planEnds.map { $0 <= now() } ?? false) }

    /// May this person trace, point to or guide to a friend?
    var canTraceFriends: Bool { !Self.friendTracingRequiresPayment || (isPaid && !planHasEnded) }

    /// Time left on a plan that ends, for showing "ends in 2 h"; nil when it does not end or nothing is bought.
    func timeLeft() -> TimeInterval? {
        guard isPaid, let planEnds else { return nil }
        return max(0, planEnds.timeIntervalSince(now()))
    }

    /// Flip to `true` (together with PLAN_CHECK=on on the server) once real purchases exist: then the server's answer is the only
    /// truth and an empty answer removes a plan. Until then a verified purchase still grants a plan, but an empty answer does
    /// not wipe the test unlock.
    static let serverIsAuthoritative = false

    /// Applies what the server says (after verifying Apple's signed purchase). The phone never decides a plan by itself.
    func applyServerPlan(until: Double?, forever: Bool) {
        let end = until.map { Date(timeIntervalSince1970: $0) }
        if forever || (end.map { $0 > now() } ?? false) {
            isPaid = true
            planEnds = forever ? nil : end
        } else if Self.serverIsAuthoritative {
            isPaid = false; planEnds = nil
        } else {
            return
        }
        defaults.set(isPaid, forKey: key)
        defaults.set(planEnds?.timeIntervalSince1970 ?? 0, forKey: endKey)
        syncReminder()
    }

    /// Dummy purchase for now: no money moves. `hours` makes it a timed pass that stacks on whatever is left, like a real one.
    /// Replaced by the StoreKit purchase and restore.
    func unlockForTesting(hours: Double? = nil) {
        isPaid = true
        defaults.set(true, forKey: key)
        if let hours {
            let start = max(now(), planEnds ?? now())
            planEnds = start.addingTimeInterval(hours * 3600)
        } else {
            planEnds = nil
        }
        defaults.set(planEnds?.timeIntervalSince1970 ?? 0, forKey: endKey)
        syncReminder()
    }

    func lockForTesting() {
        isPaid = false; planEnds = nil
        defaults.set(false, forKey: key); defaults.set(0, forKey: endKey)
        syncReminder()
    }

    private func syncReminder() {
        if isPaid, let planEnds, planEnds > now() { reminder?.schedule(endsAt: planEnds) } else { reminder?.cancel() }
    }
}
