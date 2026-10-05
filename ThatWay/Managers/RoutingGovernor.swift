//
//  RoutingGovernor.swift
//  ThatWay
//
//  Everything about *when* a routing request is allowed to go out, as opposed to what it asks —
//  minimum spacing between requests, one in flight at a time, reroute cooldown/cap, and the
//  capped-backoff retry loop that keeps guidance alive through a flaky connection instead of
//  ever giving up and dropping back to Point mode.
//
//  The actual backoff/cooldown *numbers* (`RoutingConfig`) and the pure scheduling math
//  (`backoffDelay`, `canStartReroute`) are kept free of async/Task plumbing on purpose, so the
//  policy itself is unit-testable against an injected clock without simulating real sleeps.
//

import Combine
import CoreLocation
import Foundation

struct RoutingConfig {
    var minRequestInterval: TimeInterval = 1.1
    var rerouteCooldown: TimeInterval = 15
    var maxReroutesPerWindow: Int = 4
    var rerouteWindow: TimeInterval = 300
    /// Capped exponential backoff for a retryable failure: 2, 4, 8, 16, then holds at 30s.
    var backoffSchedule: [TimeInterval] = [2, 4, 8, 16, 30]
    /// +/- jitter applied to each computed backoff, seconds.
    var jitter: TimeInterval = 0.5
}

@MainActor
final class RoutingGovernor: ObservableObject {
    @Published private(set) var currentFailure: RouteFailure?
    @Published private(set) var nextRetryAt: Date?

    private let provider: RoutingProvider
    private let config: RoutingConfig
    private let connectivity: ConnectivityMonitoring
    private let now: () -> Date
    private let randomJitter: () -> Double

    private var lastRequestAt: Date?
    private var rerouteTimestamps: [Date] = []
    private var skipCurrentWait = false

    init(
        provider: RoutingProvider,
        config: RoutingConfig = RoutingConfig(),
        connectivity: ConnectivityMonitoring = NetworkConnectivityMonitor(),
        now: @escaping () -> Date = Date.init,
        randomJitter: @escaping () -> Double = { Double.random(in: -1...1) }
    ) {
        self.provider = provider
        self.config = config
        self.connectivity = connectivity
        self.now = now
        self.randomJitter = randomJitter
        self.connectivity.onChange = { [weak self] connected in
            guard connected else { return }
            self?.skipCurrentWait = true
        }
    }

    /// Retries indefinitely on a retryable failure for as long as the caller keeps awaiting it —
    /// cancel the enclosing `Task` (guidance ending) to stop. Returns `nil` only for a
    /// non-retryable failure or cancellation; a successful route always clears `currentFailure`.
    func fetchInitial(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async -> Route? {
        await fetchWithRetry(from: origin, to: destination, profile: profile)
    }

    /// A reroute can only *start* inside the cooldown/cap — once started (because the traveller
    /// is still off the planned route), it retries exactly like `fetchInitial` until it
    /// succeeds, is cancelled, or the caller stops awaiting it.
    func fetchReroute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async -> Route? {
        guard canStartReroute(now: now()) else {
            currentFailure = .rateLimited
            nextRetryAt = nextRerouteWindowOpensAt()
            return nil
        }
        rerouteTimestamps.append(now())
        return await fetchWithRetry(from: origin, to: destination, profile: profile)
    }

    /// Skips the remainder of any backoff wait and retries immediately — wired to a "Retry now"
    /// button, and fired automatically when connectivity comes back.
    func retryNow() {
        skipCurrentWait = true
    }

    func reset() {
        currentFailure = nil
        nextRetryAt = nil
    }

    // MARK: - Retry loop

    private func fetchWithRetry(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: TravelProfile) async -> Route? {
        var attempt = 0
        while !Task.isCancelled {
            await waitForMinInterval()
            if Task.isCancelled { return nil }
            lastRequestAt = now()
            do {
                let route = try await provider.route(from: origin, to: destination, profile: profile)
                currentFailure = nil
                nextRetryAt = nil
                return route
            } catch {
                // A superseded or cancelled request is not a failure — never surface it.
                if Task.isCancelled || error is CancellationError { return nil }
                let routingError = (error as? RoutingError) ?? .invalidResponse
                let failure = RouteFailure.from(routingError, profile: profile, isConnected: connectivity.isConnected)
                currentFailure = failure
                guard failure.isRetryable else {
                    nextRetryAt = nil
                    return nil
                }
                let delay = backoffDelay(attempt: attempt, retryAfter: retryAfter(from: error))
                attempt += 1
                nextRetryAt = now().addingTimeInterval(delay)
                let interrupted = await interruptibleSleep(delay)
                if Task.isCancelled { return nil }
                _ = interrupted // early wake (retryNow/reconnect) just means: loop again sooner
            }
        }
        return nil
    }

    private func retryAfter(from error: Error) -> TimeInterval? {
        guard case .rateLimited(let retryAfter) = error as? RoutingError else { return nil }
        return retryAfter
    }

    private func waitForMinInterval() async {
        guard let lastRequestAt else { return }
        let elapsed = now().timeIntervalSince(lastRequestAt)
        let remaining = config.minRequestInterval - elapsed
        guard remaining > 0 else { return }
        _ = await interruptibleSleep(remaining)
    }

    /// Sleeps in short ticks so `retryNow()`/a reconnect can cut it short without cancelling the
    /// surrounding retry loop entirely. Returns `true` if it was cut short.
    @discardableResult
    private func interruptibleSleep(_ seconds: TimeInterval) async -> Bool {
        guard seconds > 0 else { return false }
        let tickNanoseconds: UInt64 = 200_000_000
        var remaining = seconds
        while remaining > 0 {
            if Task.isCancelled { return false }
            if skipCurrentWait {
                skipCurrentWait = false
                return true
            }
            try? await Task.sleep(nanoseconds: tickNanoseconds)
            remaining -= 0.2
        }
        return false
    }

    // MARK: - Pure policy (unit-testable without any async/sleep)

    /// Exponential backoff off `config.backoffSchedule`, holding at its last value, plus
    /// jitter — or exactly `retryAfter` when the server told us one (a 429's `Retry-After`).
    func backoffDelay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return max(0, retryAfter) }
        let schedule = config.backoffSchedule
        let base = schedule.isEmpty ? 0 : schedule[min(attempt, schedule.count - 1)]
        return max(0, base + randomJitter() * config.jitter)
    }

    /// Whether a *new* reroute attempt cycle is allowed to start right now, per the cooldown and
    /// the rolling cap. Pruning old timestamps here (rather than on a timer) keeps this a pure
    /// function of `now` and `rerouteTimestamps` — easy to unit test.
    func canStartReroute(now currentTime: Date) -> Bool {
        rerouteTimestamps.removeAll { currentTime.timeIntervalSince($0) > config.rerouteWindow }
        if let last = rerouteTimestamps.last, currentTime.timeIntervalSince(last) < config.rerouteCooldown {
            return false
        }
        return rerouteTimestamps.count < config.maxReroutesPerWindow
    }

    private func nextRerouteWindowOpensAt() -> Date? {
        guard let last = rerouteTimestamps.last else { return nil }
        return last.addingTimeInterval(config.rerouteCooldown)
    }
}
