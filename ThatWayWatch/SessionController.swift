//
//  SessionController.swift
//  ThatWayWatch
//
//  Test 1: what keeps the app alive with the wrist down?
//    A — a background location session: `allowsBackgroundLocationUpdates` + `CLBackgroundActivitySession`
//        (needs the `location` background mode).
//    B — an HKWorkoutSession (running or cycling), `workout-processing` background mode. The session is
//        started and ended but NO workout builder is ever created, so nothing can be saved to Health:
//        the workout is discarded by construction.
//  Every 30 s a tick (update counts, battery, thermal state) goes to the spike log; every minute a
//  heartbeat tap can prove the app is still running while the screen is off.
//

import SwiftUI
import CoreLocation
import HealthKit
import WatchKit

@MainActor
final class SessionController: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    enum Kind: String, CaseIterable, Identifiable {
        case location = "A · location", running = "B · workout run", cycling = "B · workout cycle"
        var id: String { rawValue }
        var logLabel: String {
            switch self { case .location: return "A-location"; case .running: return "B-run"; case .cycling: return "B-cycle" }
        }
    }

    @Published var kind: Kind = .location
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Stopped"
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var batteryStart = -1
    @Published private(set) var batteryNow = -1
    @Published var heartbeat = true

    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var background: CLBackgroundActivitySession?
    private var timer: Timer?
    private var startedAt = Date()
    private var tickCount = 0
    private var lastLoc = 0, lastHead = 0
    private weak var model: WatchModel?

    func start(model: WatchModel) async {
        guard !isRunning else { return }
        guard !model.blockedByDriving else { status = "Not while driving"; return }
        self.model = model
        model.resetCounters()
        lastLoc = 0; lastHead = 0; tickCount = 0
        model.start()
        SpikeLog.shared.open(label: kind.logLabel)
        startedAt = Date()
        batteryStart = model.batteryPercent
        let c = model.blender.config
        SpikeLog.shared.write(["type": "session", "kind": kind.logLabel, "battery": batteryStart,
                               "courseEnter": c.courseEnterSpeed, "magEnter": c.magnetometerEnterSpeed, "dwell": c.dwell,
                               "os": WKInterfaceDevice.current().systemVersion, "model": WKInterfaceDevice.current().model])
        switch kind {
        case .location:
            // CoreLocation asserts (crashes) if the location background mode isn't declared: fail politely instead.
            let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
            guard modes.contains("location") else {
                status = "A unavailable: location background mode missing"
                SpikeLog.shared.write(["type": "error", "where": "locationMode", "message": "UIBackgroundModes lacks location"])
                SpikeLog.shared.close()
                return
            }
            model.manager.allowsBackgroundLocationUpdates = true
            background = CLBackgroundActivitySession()
            status = "A running"
        case .running, .cycling:
            model.manager.allowsBackgroundLocationUpdates = false
            do {
                try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
                let config = HKWorkoutConfiguration()
                config.activityType = kind == .running ? .running : .cycling
                config.locationType = .outdoor
                let session = try HKWorkoutSession(healthStore: health, configuration: config)
                session.delegate = self
                workout = session
                session.startActivity(with: Date())
                status = "B running"
            } catch {
                status = "B failed: \(error.localizedDescription)"
                SpikeLog.shared.write(["type": "error", "where": "workoutStart", "message": error.localizedDescription])
                SpikeLog.shared.close()
                return
            }
        }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        guard isRunning else { return }
        timer?.invalidate(); timer = nil
        tick(final: true)
        background?.invalidate(); background = nil
        model?.manager.allowsBackgroundLocationUpdates = false
        workout?.end(); workout = nil          // no builder was ever created: nothing is saved to Health
        isRunning = false
        status = "Stopped"
        SpikeLog.shared.close()
    }

    func notePhase(_ phase: ScenePhase) {
        guard isRunning, let model else { return }
        SpikeLog.shared.write(["type": "phase", "phase": String(describing: phase),
                               "loc": model.locationUpdates, "head": model.headingUpdates, "battery": model.batteryPercent])
    }

    private func tick(final: Bool = false) {
        guard let model else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        batteryNow = model.batteryPercent
        tickCount += 1
        SpikeLog.shared.write([
            "type": final ? "final" : "tick", "elapsed": Int(elapsed), "battery": batteryNow,
            "locSince": model.locationUpdates - lastLoc, "headSince": model.headingUpdates - lastHead,
            "locTotal": model.locationUpdates, "headTotal": model.headingUpdates,
            "thermal": ProcessInfo.processInfo.thermalState.rawValue, "source": model.source.rawValue,
        ])
        lastLoc = model.locationUpdates; lastHead = model.headingUpdates
        // A tap every other tick (once a minute) so a wrist-down session proves it is alive.
        if heartbeat, !final, tickCount % 2 == 0 {
            WKInterfaceDevice.current().play(.click)
            SpikeLog.shared.write(["type": "heartbeat"])
        }
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            SpikeLog.shared.write(["type": "workoutState", "to": toState.rawValue, "from": fromState.rawValue])
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.status = "B error: \(message)"
            SpikeLog.shared.write(["type": "error", "where": "workoutSession", "message": message])
        }
    }
}
