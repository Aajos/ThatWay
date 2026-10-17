//
//  PushRegistrar.swift
//  ThatWay
//
//  Remote push, so a request to trace you (or "X is still tracing you") reaches you with ThatWay closed. The phone gives Apple's
//  push service a token; the app hands it to the server (`PUT /devices`), and the server sends through APNs with the team's key.
//  A push only says who is asking, never a place, distance or time. While the app is in front the in-app banner is the notice,
//  so no system banner is shown on top of it. Signing out removes this phone's token from the account.
//

import UIKit
import UserNotifications

final class PushRegistrar: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The newest token Apple gave this phone, and who to tell. (Set by AppModel.)
    nonisolated(unsafe) static var token: String?
    nonisolated(unsafe) static var onToken: ((String) -> Void)?

    /// Which Apple push server this build's token belongs to.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.token = hex
        Self.onToken?(hex)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []          // in front: the banner inside the app already says it
    }
}
