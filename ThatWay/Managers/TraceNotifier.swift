//
//  TraceNotifier.swift
//  ThatWay
//
//  A local notification for an incoming trace request. This is *not* remote push: without the paid Apple Developer
//  Program there is no push entitlement, so a request is only noticed while the app is running (in front, or kept
//  alive by an active trip). Real push (APNs) is the v1.1 work and replaces this seam without touching the manager.
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
        content.body = "Open ThatWay to accept or decline. Nothing is shared until you accept."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func clearIncoming() {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
