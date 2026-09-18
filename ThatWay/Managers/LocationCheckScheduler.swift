//
//  LocationCheckScheduler.swift
//  ThatWay
//
//  Replaces continuously re-checking the route on every tick with adaptive polling: while
//  guiding, the corridor/off-route check runs once per interval instead of ~11 times a
//  second, cutting how often the expensive work (route-distance math, and any reroute fetch
//  it triggers) actually runs. Point mode never polls at all — there's no route, so a
//  corridor check has nothing to check against.
//

import Foundation
import Combine

/// Owns *when* a location-driven guidance check happens — not the check itself, which stays
/// with RoutingManager/AppModel. This keeps the polling policy (intervals, start/stop,
/// non-overlapping restarts) in one place, independent of whatever the check actually does.
@MainActor
final class LocationCheckScheduler: ObservableObject {
    @Published private(set) var isPolling = false

    private var timer: Timer?
    private var isChecking = false
    private var activityProvider: () -> GuidanceActivity = { .walking }
    private var onCheck: () -> Void = {}

    /// 10s walking (course changes slowly on foot), 3s driving (needs responsive course
    /// correction at speed). Re-read from `activityProvider` on every cycle, so a walking→
    /// driving change takes effect on the very next check without needing an explicit restart.
    private func interval(for activity: GuidanceActivity) -> TimeInterval {
        activity == .driving ? 3 : 10
    }

    /// Starts polling for Guidance mode — a no-op, and stops anything already running, for
    /// Point mode, since there's no active route to check a corridor against. Safe to call
    /// repeatedly (e.g. every time mode/activity might have changed): if already polling in
    /// Guidance, the running cycle just continues rather than resetting the clock.
    func start(mode: NavMode, activityProvider: @escaping () -> GuidanceActivity, onCheck: @escaping () -> Void) {
        self.activityProvider = activityProvider
        self.onCheck = onCheck
        guard mode == .guidance else {
            stop()
            return
        }
        guard timer == nil else { return }
        isPolling = true
        scheduleNext()
    }

    /// Stops polling outright — called on exiting guidance, arriving, and (briefly, around
    /// the fetch) on a reroute, since the old route's corridor no longer applies.
    func stop() {
        timer?.invalidate()
        timer = nil
        isPolling = false
        isChecking = false
    }

    private func scheduleNext() {
        let delay = interval(for: activityProvider())
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
    }

    /// Runs one check, then — only once it's finished — schedules the next one. A
    /// non-repeating timer rearmed after each check, rather than a repeating one, is what
    /// guarantees checks never overlap even if a check ever took longer than the interval.
    private func fire() {
        guard !isChecking else { return }
        isChecking = true
        onCheck()
        isChecking = false
        guard isPolling else { return }
        scheduleNext()
    }
}
