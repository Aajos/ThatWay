//
//  TraceNotifier.swift
//  ThatWay
//
//  Local notifications for trace requests and plan endings. This is *not* remote push: remote push needs the app's APNs key
//  and a sender on the server, which are not set up yet. So a request or a "still tracing you" is only noticed while the app
//  is running (in front, or kept alive by a trip). Real push (APNs) replaces this seam without touching the managers.
//  The plan-ending reminder does not need push: it is scheduled on this phone when the plan starts.
//

import Foundation
import UserNotifications

@MainActor
final class LocalTraceNotifier: TraceNotifying {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "trace.incoming"

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func incomingRequest(from name: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(name) wants to trace you"
        content.body = "Open ThatWay to review it. Nothing is shared unless you say yes."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func clearIncoming() {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func stillTracing(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(name) is still tracing you"
        content.body = "Open ThatWay to stop it."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "trace.still.\(name)", content: content, trigger: nil))
    }
}

/// "Your trace plan ends in 30 minutes": scheduled on this phone, no server involved.
@MainActor
protocol PlanReminding: AnyObject {
    func schedule(endsAt: Date)
    func cancel()
}

@MainActor
final class LocalPlanReminder: PlanReminding {
    static let lead: TimeInterval = 30 * 60
    private let center = UNUserNotificationCenter.current()
    private let identifier = "plan.ending"
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func schedule(endsAt: Date) {
        cancel()
        let fireAt = endsAt.addingTimeInterval(-Self.lead)
        guard fireAt > now() else { return }                     // already inside the last half hour: nothing to wait for
        let content = UNMutableNotificationContent()
        content.title = "Your trace plan ends in 30 minutes"
        content.body = "Any traces you have going end with it. Open ThatWay to renew."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSince(now()), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
