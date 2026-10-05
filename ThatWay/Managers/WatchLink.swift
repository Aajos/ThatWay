//
//  WatchLink.swift
//  ThatWay
//
//  Tells the paired Apple Watch which travel mode the iPhone is in. The watch uses it for one safety rule: while
//  the phone is in Drive mode the watch refuses to guide and closes (looking at a wrist while driving is unsafe).
//  Only the mode is sent (see `WatchSync`): never places, routes or coordinates. The latest mode is kept as the
//  WatchConnectivity application context, so a watch that wakes later still reads the current one.
//

import Foundation
import WatchConnectivity
import ThatWayCore

@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
    private var latest: TravelMode?

    func start(mode: TravelMode) {
        latest = mode
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ mode: TravelMode) {
        latest = mode
        push()
    }

    private func push() {
        guard WCSession.isSupported(), let mode = latest else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchSync.payload(mode: mode)
        try? session.updateApplicationContext(payload)           // latest wins; delivered even if the watch app is not running
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }   // immediate when it is
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: reactivate so the new one gets the mode too.
        session.activate()
    }
}
