//
//  TraceManager.swift
//  ThatWay
//
//  "Trace a friend": point at a friend at any range, once they have agreed. The flow:
//    you tap a friend -> request (they see "wants to trace you") -> they accept -> both phones share a position with each
//    other for up to 30 minutes -> the pill points at them with distance; inside about 40 m Ultra Wideband takes over.
//
//  Safety is built into the shape of it:
//    - nothing is shared until the other person accepts, and either side can stop at any moment;
//    - the server only relays a position to the partner of an active session; the app shows direction and distance,
//      never a coordinate and never a map;
//    - coordinates live in memory only: not persisted, not logged, not sent to the watch.
//
//  The network and the UWB layer sit behind small protocols so the whole flow is unit-tested without hardware.
//

import Foundation
import CoreLocation
import Combine
import ThatWayCore

@MainActor
protocol TraceAPI: AnyObject {
    func traceRequest(friendId: String) async throws
    func traceList() async throws -> [TraceSession]
    func traceRespond(friendId: String, accept: Bool) async throws
    func tracePosition(friendId: String, coordinate: CLLocationCoordinate2D, accuracy: Double) async throws
    func traceEnd(friendId: String) async
}

@MainActor
protocol TraceNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    /// Tell the person someone wants to trace them (shown only when the app is not in front).
    func incomingRequest(from name: String)
    func clearIncoming()
}

enum TraceState: Equatable {
    /// I asked; waiting for their answer.
    case asking(Friend)
    /// They asked me.
    case incoming(Friend)
    /// Both agreed. The distance and direction are in `TraceManager.reading`.
    case active(Friend)
    /// A short message in place of the pill ("Sam declined", "Sam ended the trace").
    case notice(String)
}

@MainActor
final class TraceManager: ObservableObject {
    @Published private(set) var state: TraceState?
    @Published private(set) var reading: TraceReading?
    @Published private(set) var errorMessage: String?
    /// The friend the compass is currently pointing or guiding to (the pill shows "Stop following" for them).
    @Published private(set) var following: String?

    /// Wired by AppModel: point or guide to the friend's live position.
    var onFollow: ((Friend, CLLocationCoordinate2D, _ guide: Bool) -> Void)?
    var onStopFollowing: (() -> Void)?
    /// A fresh position for the friend being followed (the destination moves with them).
    var onFriendPosition: ((Friend, CLLocationCoordinate2D) -> Void)?

    // MARK: Dependencies
    private let api: TraceAPI
    private let ranging: ProximityRanging
    private let notifier: TraceNotifying
    private let friends: () -> [Friend]
    private let refreshFriends: () async -> Void
    private let myPosition: () -> CLLocationCoordinate2D?
    private let myAccuracy: () -> Double
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void
    private let loopEnabled: Bool

    // MARK: Timing (seconds)
    private let activeInterval: TimeInterval
    private let pendingInterval: TimeInterval
    private let idleInterval: TimeInterval
    private let noticeLife: TimeInterval = 5
    private let uploadEvery: TimeInterval = 3
    private let uploadAtLeastEvery: TimeInterval = 15
    private let uploadMoveMetres: Double = 3

    // MARK: Working state (memory only)
    private var loop: Task<Void, Never>?
    private var fusion = TraceFusion()
    private var peerPosition: TracePeerPosition?
    private var peerPositionAt = Date.distantPast
    private var uwbRunning = false
    private var lastUpload: (at: Date, coordinate: CLLocationCoordinate2D)?
    private var noticeUntil = Date.distantPast
    private var dismissed = Set<String>()          // declined sessions already shown, so they don't come back
    private var announced = Set<String>()          // incoming sessions already notified
    private var sceneActive = true
    private var lastFriendsRefresh = Date.distantPast
    private var consecutiveFailures = 0
    private var askedForNotifications = false
    /// Bumped by every local action (ask, answer, end). A poll that was already in flight when one happened carries an
    /// older epoch and is discarded, so it cannot bring back a trace the person has just ended.
    private var epoch = 0
    private var notificationShown = false

    init(api: TraceAPI,
         ranging: ProximityRanging,
         notifier: TraceNotifying,
         friends: @escaping () -> [Friend],
         refreshFriends: @escaping () async -> Void = {},
         myPosition: @escaping () -> CLLocationCoordinate2D?,
         myAccuracy: @escaping () -> Double = { 10 },
         activeInterval: TimeInterval = 3,
         pendingInterval: TimeInterval = 4,
         idleInterval: TimeInterval = 10,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
         loopEnabled: Bool = true) {
        self.api = api; self.ranging = ranging; self.notifier = notifier; self.friends = friends
        self.refreshFriends = refreshFriends; self.myPosition = myPosition; self.myAccuracy = myAccuracy
        self.activeInterval = activeInterval; self.pendingInterval = pendingInterval; self.idleInterval = idleInterval
        self.now = now; self.sleep = sleep; self.loopEnabled = loopEnabled
        ranging.onReading = { [weak self] in self?.recomputeReading() }
    }

    var isBusy: Bool {
        switch state {
        case .asking, .incoming, .active: return true
        case .notice, .none: return false
        }
    }

    #if DEBUG
    /// Simulator aid (the simulator has no friends or radio): `-tw-preview-trace asking|incoming|active|uwb|notice`.
    func previewState(_ name: String) {
        let sam = Friend(id: "preview", username: "sam", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
        switch name {
        case "asking": state = .asking(sam)
        case "incoming": state = .incoming(sam)
        case "active": state = .active(sam); reading = TraceReading(meters: 8_240_000, band: .far, source: .gps, trueBearing: 40, peerAgeSeconds: 3)
        case "uwb": state = .active(sam); reading = TraceReading(meters: 4.2, band: .veryClose, source: .uwb, relativeBearing: 25)
        default: state = .notice("sam declined")
        }
    }
    #endif

    // MARK: Lifecycle

    /// Begin watching for requests and sessions (call once signed in).
    func start() {
        if !askedForNotifications { askedForNotifications = true; notifier.requestAuthorizationIfNeeded() }
        guard loopEnabled, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                await self.sleep(self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
    }

    /// Sign-out or a switch of account: drop everything, tell the server nothing more.
    func reset() {
        stop()
        ranging.stop(); uwbRunning = false
        state = nil; reading = nil; errorMessage = nil
        if following != nil { following = nil; onStopFollowing?() }
        peerPosition = nil; lastUpload = nil; fusion.reset()
        dismissed.removeAll(); announced.removeAll()
        epoch += 1
        clearNotification()
    }

    /// Background: with no trace going there is nothing worth polling for. An active trace keeps running while the app
    /// is alive (a trip in progress keeps it alive); with a suspended app nothing runs, which is the safe default.
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { start() } else if !isBusy { stop() }
    }

    private var interval: TimeInterval {
        switch state {
        case .active: return activeInterval
        case .asking, .incoming: return pendingInterval
        case .notice: return 2
        default: return idleInterval
        }
    }

    /// Whether this phone is sharing its position right now (an accepted trace). Drives background location, so the
    /// trace does not stop partway through a trip when the screen locks.
    var isSharing: Bool { if case .active = state { return true } else { return false } }

    // MARK: Following

    /// Point (or guide) the compass at the friend's live position. A moving target: the destination follows them.
    func follow(guide: Bool) {
        guard case .active(let friend) = state, let peer = peerPosition else { return }
        following = friend.id
        onFollow?(friend, peer.coordinate, guide)
    }

    func stopFollowing() {
        guard following != nil else { return }
        following = nil
        onStopFollowing?()
    }

    /// AppModel tells us when the destination was cleared some other way (the cross on the destination card).
    func followingEnded() { following = nil }

    // MARK: Actions

    /// Ask a friend to be traced. Nothing is shared until they accept.
    func request(_ friend: Friend) async {
        guard !isBusy else { return }
        epoch += 1
        errorMessage = nil
        state = .asking(friend)
        do {
            try await api.traceRequest(friendId: friend.id)
            start()
        } catch {
            state = nil
            errorMessage = error.localizedDescription
        }
    }

    func accept() async { await answer(accept: true) }
    func decline() async { await answer(accept: false) }

    private func answer(accept: Bool) async {
        guard case .incoming(let friend) = state else { return }
        epoch += 1
        errorMessage = nil
        clearNotification()
        do {
            try await api.traceRespond(friendId: friend.id, accept: accept)
            if accept { state = .active(friend); await poll() } else { state = nil }
        } catch {
            errorMessage = error.localizedDescription
            await poll()                       // the request may be gone: the next poll says so
        }
    }

    /// Stop now (cancel a request, or end a session). Either side can do this at any time.
    func end() async {
        let friend: Friend?
        switch state {
        case .asking(let f), .incoming(let f), .active(let f): friend = f
        default: friend = nil
        }
        epoch += 1
        stopRanging()
        state = nil; reading = nil; peerPosition = nil; lastUpload = nil; fusion.reset()
        stopFollowing()
        clearNotification()
        if let friend { await api.traceEnd(friendId: friend.id) }
    }

    // MARK: Polling

    /// One poll: fetch, reconcile, and (when active) share my position and manage the radio. The background loop calls
    /// this; tests call it directly.
    func poll() async {
        // A notice is only a few seconds long.
        if case .notice = state, now() >= noticeUntil { state = nil }

        let startedAt = epoch
        let sessions: [TraceSession]
        do {
            sessions = try await api.traceList()
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1       // a dropped connection must not end a trace: keep what we have
            return
        }
        guard startedAt == epoch else { return }      // something local happened while this was in flight
        await reconcile(sessions)
        if case .active(let friend) = state { await keepActive(friend) }
    }

    private func reconcile(_ sessions: [TraceSession]) async {
        let rank: [TraceStatus: Int] = [.active: 0, .incoming: 1, .outgoing: 2, .declined: 3]
        let fresh = sessions.filter { !($0.status == .declined && dismissed.contains($0.sessionId)) }
        let current = fresh.min { (rank[$0.status] ?? 9) < (rank[$1.status] ?? 9) }

        guard let current else {
            // Nothing on the server. If we thought something was going on, it ended on the other side (or timed out).
            switch state {
            case .asking(let f): showNotice("\(f.username) didn't answer")
            case .active(let f): stopFollowing(); showNotice("\(f.username) ended the trace")
            case .incoming: state = nil
            default: break
            }
            stopRanging(); peerPosition = nil
            clearNotification()
            return
        }

        guard let friend = friends().first(where: { $0.id == current.friendId }) else {
            // A request from someone not in our list yet (just accepted elsewhere): refresh the list, at most once a minute.
            if now().timeIntervalSince(lastFriendsRefresh) > 60 { lastFriendsRefresh = now(); await refreshFriends() }
            return
        }

        switch current.status {
        case .outgoing:
            if case .asking = state {} else if !isNoticeShowing { state = .asking(friend) }
        case .incoming:
            if case .incoming = state {} else { state = .incoming(friend) }
            if !announced.contains(current.sessionId) {
                announced.insert(current.sessionId)
                if !sceneActive { notifier.incomingRequest(from: friend.username); notificationShown = true }
            }
        case .active:
            if case .active = state {} else { state = .active(friend); fusion.reset(); lastUpload = nil }
            clearNotification()
            if let peer = current.peer {
                peerPosition = peer; peerPositionAt = now()
                if following == friend.id { onFriendPosition?(friend, peer.coordinate) }
            } else if now().timeIntervalSince(peerPositionAt) > 90 {
                peerPosition = nil
            }
        case .declined:
            dismissed.insert(current.sessionId)
            showNotice("\(friend.username) declined")
            stopRanging()
        }
    }

    private func clearNotification() {
        guard notificationShown else { return }
        notificationShown = false
        notifier.clearIncoming()
    }

    private var isNoticeShowing: Bool { if case .notice = state { return true } else { return false } }

    private func showNotice(_ text: String) {
        state = .notice(text)
        noticeUntil = now().addingTimeInterval(noticeLife)
        reading = nil
    }

    // MARK: While active

    private func keepActive(_ friend: Friend) async {
        // 1. Share my position, when it is worth sending.
        if let me = myPosition() {
            let due: Bool
            if let last = lastUpload {
                let elapsed = now().timeIntervalSince(last.at)
                let moved = CompassManager.distance(from: last.coordinate, to: me)
                due = elapsed >= uploadAtLeastEvery || (elapsed >= uploadEvery && moved >= uploadMoveMetres)
            } else { due = true }
            if due {
                do {
                    try await api.tracePosition(friendId: friend.id, coordinate: me, accuracy: myAccuracy())
                    lastUpload = (now(), me)
                } catch { /* the next tick tries again; a failed upload must never end a trace */ }
            }
        }

        // 2. The distance by GPS decides whether Ultra Wideband should be trying.
        let gpsMeters: Double? = {
            guard let me = myPosition(), let peer = peerPosition else { return nil }
            return CompassManager.distance(from: me, to: peer.coordinate)
        }()
        let want = ranging.capability.canRange && TraceFusion.wantsUWB(gpsMeters: gpsMeters, running: uwbRunning)
        if want, !uwbRunning {
            ranging.start(with: friend); uwbRunning = true
        } else if !want, uwbRunning {
            stopRanging()
        }

        recomputeReading()
    }

    private func stopRanging() {
        if uwbRunning { ranging.stop(); uwbRunning = false }
    }

    /// Called every poll and on every UWB reading.
    private func recomputeReading() {
        guard case .active = state else { return }
        let uwb = ranging.latestReading.map { (reading: $0.reading, ageSeconds: now().timeIntervalSince($0.at)) }
        // The age shown is how old the friend's position is *now*, not when it was fetched.
        let aged = peerPosition.map {
            TracePeerPosition(latitude: $0.latitude, longitude: $0.longitude, accuracy: $0.accuracy,
                              ageSeconds: $0.ageSeconds + now().timeIntervalSince(peerPositionAt))
        }
        reading = fusion.reading(me: myPosition(), peer: aged, uwb: uwb)
    }
}

// MARK: - Network (the same authenticated client as friends)

extension FriendsManager: TraceAPI {
    func traceRequest(friendId: String) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/trace/request", body: ["friendId": friendId])
    }

    func traceList() async throws -> [TraceSession] {
        try await request(method: "GET", path: "/trace")
    }

    func traceRespond(friendId: String, accept: Bool) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/trace/respond",
                                                 body: ["friendId": friendId, "action": accept ? "accept" : "decline"])
    }

    func tracePosition(friendId: String, coordinate: CLLocationCoordinate2D, accuracy: Double) async throws {
        let _: EmptyResponse = try await request(method: "PUT", path: "/trace/position", body: [
            "friendId": friendId, "lat": coordinate.latitude, "lon": coordinate.longitude, "acc": max(0, accuracy),
        ])
    }

    func traceEnd(friendId: String) async {
        let _: EmptyResponse? = try? await request(method: "DELETE", path: "/trace/\(friendId)")
    }
}
