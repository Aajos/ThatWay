//
//  PhoneLink.swift
//  ThatWayWatch
//
//  Listens for the iPhone's travel mode (see `WatchSync`). The mode arrives as the WatchConnectivity application
//  context, which the system keeps, so a watch app that launches later still reads the phone's latest mode.
//  If the phone is not paired or has not sent one, nothing is blocked.
//

import Foundation
import WatchConnectivity
import ThatWayCore

@MainActor
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    /// Called whenever a travel mode from the phone arrives (including the stored one at launch).
    var onMode: ((TravelMode) -> Void)?
    /// Called when the phone reports (or ends) a "find a friend" session.
    var onProximity: ((ProximityWatchState?) -> Void)?
    @Published private(set) var lastPhoneMode: TravelMode?

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func receive(_ payload: [String: Any]) {
        if let proximity = WatchSync.proximity(from: payload) { onProximity?(proximity) }
        guard let mode = WatchSync.mode(from: payload) else { return }
        lastPhoneMode = mode
        onMode?(mode)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let stored = session.receivedApplicationContext
        Task { @MainActor in self.receive(stored) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
