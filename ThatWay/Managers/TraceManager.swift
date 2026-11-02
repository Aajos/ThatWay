//
//  TraceManager.swift
//  ThatWay
//
//  "Trace a friend", the permission model (see docs/vault/features/trace-grants.md):
//
//    - The person being TRACED grants a permission to ONE tracer, one-way, for a length of time they choose (15 minutes to
//      24 hours, never more than was asked for). It ends by itself, whether or not anyone is watching.
//    - The TRACER asks, then looks at one friend at a time and may hold up to ten permissions. They see only "Accepted" and,
//      if anything goes wrong for any reason, "User cannot be traced, error has occurred". Never how long they have.
//    - The tracer's own position is never uploaded. Only a rounded distance band travels with their look.
//    - The traced phone uploads its position only while someone may see it, in the background too (blue indicator), with
//      "While Using" location and Precise on (SharingReadiness is checked before allowing, and the banner says when it lapses).
//      A look is not continuous: "request a new location" is limited to once every 2 minutes, and what comes back says how old
//      it is. Inside about 200 m Ultra Wideband takes over once both apps are open.
//
//  Every other safety decision is the server's, every time (backend/lambda/grants). This class only asks, shows and obeys.
//  Stopping a trace needs no authentication; allowing one needs the phone's owner (OwnerAuthenticating).
//
//  The network, the radio, the notifications and the owner check sit behind small protocols so all of it is tested without
//  hardware, a server or a screen. Coordinates live in memory only: not persisted, not logged, not sent to the watch.
//

import Foundation
import CoreLocation
import Combine
import ThatWayCore

@MainActor
protocol TraceAPI: AnyObject {
    func grantsSnapshot() async throws -> GrantsSnapshot
    func requestTrace(friendId: String, hours: Double) async throws
    func answerTrace(tracerId: String, grant: Bool, hours: Double?, kind: GrantKind?, consentVersion: String?) async throws
    func revokeTrace(tracerId: String) async throws
    func releaseTrace(traceeId: String) async
    func uploadPosition(_ coordinate: CLLocationCoordinate2D, accuracy: Double) async throws
    func locate(traceeId: String, distanceMeters: Double?) async throws -> LocateResult
    /// Re-reads the stored position shortly after a real request, to collect the fresh fix that request made the other phone send.
    func locateFollowUp(traceeId: String) async throws -> LocateResult
}

@MainActor
protocol TraceNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    /// Someone asked to trace you (shown only when the app is not in front).
    func incomingRequest(from name: String)
    func clearIncoming()
    /// "X is still tracing you" (shown only when the app is not in front).
    func stillTracing(name: String)
}

/// What the tracer's pill is showing.
enum TraceState: Equatable {
    /// I asked; waiting for their answer.
    case waiting(Friend)
    /// They said yes. The direction and distance are in `TraceManager.reading` once a location has come back.
    case active(Friend)
    /// A short message in place of the pill.
    case notice(String)
}

/// Someone asking to trace me.
struct IncomingTrace: Identifiable, Equatable {
    let friend: Friend
    let requestedHours: Double
    let requestedAt: Double?
    let expiresAt: Date?
    var id: String { friend.id }
}

/// Someone who may trace me right now.
struct Watcher: Identifiable, Equatable {
    let friend: Friend
    let kind: GrantKind
    let until: Date
    let lastLookedAt: Date?
    /// How far they were when they last looked ("under 200 m"), a band and never a number.
    let band: String?
    var id: String { friend.id }
}

enum GrantOutcome: Equatable {
    case granted
    /// The person backed out of the confirmation: nothing happened, and nothing needs saying.
    case cancelled
    case notVerified
    case failed(String)
}

@MainActor
final class TraceManager: ObservableObject {
    // MARK: As the tracer
    @Published private(set) var state: TraceState?
    @Published private(set) var reading: TraceReading?
    /// Friends I may trace right now (their permission is live). I look at one at a time.
    @Published private(set) var heldTraces: Set<String> = []
    /// What each permission is, as the traced person chose it: a one-off ends when I switch away.
    @Published private(set) var heldKinds: [String: GrantKind] = [:]
    /// The soonest I may ask for a new location; nil means now.
    @Published private(set) var locateReadyAt: Date?
    /// My own plan's end, as the server knows it (nil: no end or not checked).
    @Published private(set) var planEnds: Date?
    /// True until the first location comes back after being accepted: "Accepted" is shown in the meantime.
    @Published private(set) var justAccepted = false
    /// They said yes but their phone has not shared a location yet.
    @Published private(set) var noLocationYet = false
    /// The friend the compass is currently pointing or guiding to.
    @Published private(set) var following: String?
    /// Ultra Wideband, up close: getting closer (true), further (false), or no clear trend (nil). For "warmer / colder" when the
    /// radio gives a distance but no direction.
    @Published private(set) var closing: Bool?
    /// Waiting for the fresh position a request asked the other phone for.
    @Published private(set) var fetchingFresh = false
    /// Set when a paid action was attempted without the entitlement: the screen shows the paywall.
    @Published var needsUpgrade = false

    // MARK: As the traced person
    @Published private(set) var incoming: [IncomingTrace] = []
    @Published private(set) var watchers: [Watcher] = []
    /// "X is still tracing you. Stop?" (the server raises it at most every 30 minutes).
    @Published var stillTracing: Friend?

    @Published private(set) var errorMessage: String?
    /// Why a request could not be sent (shown once, on the screen where it was asked).
    @Published var requestError: String?

    /// Wired by AppModel: point or guide to the friend's last position.
    var onFollow: ((Friend, CLLocationCoordinate2D, _ guide: Bool) -> Void)?
    var onStopFollowing: (() -> Void)?
    /// A fresh position for the friend being followed (the destination moves with them).
    var onFriendPosition: ((Friend, CLLocationCoordinate2D) -> Void)?

    // MARK: Dependencies
    private let api: TraceAPI
    private let ranging: ProximityRanging
    private let notifier: TraceNotifying
    private let owner: OwnerAuthenticating
    private let friends: () -> [Friend]
    private let refreshFriends: () async -> Void
    private let myPosition: () -> CLLocationCoordinate2D?
    private let myAccuracy: () -> Double
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void
    private let loopEnabled: Bool
    private let isEntitled: () -> Bool

    // MARK: Timing (seconds)
    private let busyInterval: TimeInterval
    private let watchingInterval: TimeInterval
    private let idleInterval: TimeInterval
    private let noticeLife: TimeInterval = 6
    private let uploadMoveMetres: Double = 25
    private let uploadMovedAfter: TimeInterval = 30
    private let uploadAtLeastEvery: TimeInterval = 120

    // MARK: Working state (memory only)
    private var loop: Task<Void, Never>?
    private var fusion = TraceFusion()
    private var peerPosition: TracePeerPosition?
    private var peerPositionAt = Date.distantPast
    private var uwbFriendId: String?
    private var wantsPrecise = false
    private var lastUpload: (at: Date, coordinate: CLLocationCoordinate2D)?
    private var noticeUntil = Date.distantPast
    private var acceptedUntil = Date.distantPast
    private var announced = Set<String>()
    private var lastLooked: [String: Double] = [:]
    private var lookedSinceUpload = false
    private var sceneActive = true
    private var lastFriendsRefresh = Date.distantPast
    private var askedForNotifications = false
    /// Bumped by every local action. A poll that was already in flight when one happened carries an older epoch and is
    /// discarded, so it cannot bring back a trace the person has just ended.
    private var epoch = 0
    private var notificationShown = false
    private var uwbHistory: [(meters: Double, at: Date)] = []
    private var followUpTask: Task<Void, Never>?

    init(api: TraceAPI,
         ranging: ProximityRanging,
         notifier: TraceNotifying,
         owner: OwnerAuthenticating,
         friends: @escaping () -> [Friend],
         refreshFriends: @escaping () async -> Void = {},
         myPosition: @escaping () -> CLLocationCoordinate2D?,
         myAccuracy: @escaping () -> Double = { 10 },
         busyInterval: TimeInterval = 5,
         watchingInterval: TimeInterval = 10,
         idleInterval: TimeInterval = 30,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
         loopEnabled: Bool = true,
         isEntitled: @escaping () -> Bool = { true }) {
        self.api = api; self.ranging = ranging; self.notifier = notifier; self.owner = owner; self.friends = friends
        self.refreshFriends = refreshFriends; self.myPosition = myPosition; self.myAccuracy = myAccuracy
        self.busyInterval = busyInterval; self.watchingInterval = watchingInterval; self.idleInterval = idleInterval
        self.now = now; self.sleep = sleep; self.loopEnabled = loopEnabled; self.isEntitled = isEntitled
        ranging.onReading = { [weak self] in self?.recomputeReading() }
    }

    // MARK: What the screens ask

    /// The friend I am currently tracing or waiting on.
    var targetFriend: Friend? {
        switch state {
        case .waiting(let f), .active(let f): return f
        default: return nil
        }
    }

    var isBusy: Bool { targetFriend != nil }

    /// Whether this phone is sharing its position with anyone right now (someone may trace me).
    var isSharing: Bool { !watchers.isEmpty }

    /// Seconds until a new location may be asked for (0 when it may be asked now).
    func locateCountdown() -> TimeInterval { max(0, (locateReadyAt ?? .distantPast).timeIntervalSince(now())) }

    /// How old the friend's location is right now, in seconds; nil until one has arrived.
    var locationAge: TimeInterval? {
        guard let peerPosition else { return nil }
        return peerPosition.ageSeconds + now().timeIntervalSince(peerPositionAt)
    }

    #if DEBUG
    /// Simulator aid (the simulator has no friends or radio): `-tw-preview-trace waiting|active|uwb|notice|incoming|watchers`.
    func previewState(_ name: String) {
        let sam = Friend(id: "preview", username: "sam", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
        let ellie = Friend(id: "preview2", username: "ellie", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)
        switch name {
        case "waiting": state = .waiting(sam)
        case "active":
            state = .active(sam); peerPositionAt = now(); peerPosition = TracePeerPosition(latitude: 0, longitude: 0, ageSeconds: 200)
            reading = TraceReading(meters: 8_240_000, band: .far, source: .gps, trueBearing: 40, peerAgeSeconds: 200)
            heldTraces = ["preview", "preview2"]
        case "uwb": state = .active(sam); reading = TraceReading(meters: 4.2, band: .veryClose, source: .uwb, relativeBearing: 25)
        case "incoming":
            incoming = [IncomingTrace(friend: sam, requestedHours: 8, requestedAt: 1, expiresAt: now().addingTimeInterval(1500))]
        case "watchers":
            watchers = [
                Watcher(friend: sam, kind: .window, until: now().addingTimeInterval(7_200), lastLookedAt: now().addingTimeInterval(-300), band: "under 200 m"),
                Watcher(friend: ellie, kind: .oneoff, until: now().addingTimeInterval(1_500), lastLookedAt: nil, band: nil),
            ]
        default: state = .notice(TraceCopy.cannotTrace)
        }
    }
    #endif

    // MARK: Lifecycle

    /// Begin watching for requests and permissions (call once signed in).
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
        ranging.stop(); uwbFriendId = nil; wantsPrecise = false
        state = nil; reading = nil; errorMessage = nil
        incoming = []; watchers = []; stillTracing = nil; heldTraces = []; heldKinds = [:]
        locateReadyAt = nil; planEnds = nil; justAccepted = false; noLocationYet = false
        if following != nil { following = nil; onStopFollowing?() }
        peerPosition = nil; lastUpload = nil; fusion.reset()
        announced.removeAll(); lastLooked.removeAll(); lookedSinceUpload = false
        epoch += 1
        clearNotification()
    }

    /// The app leaves or returns to the front. Coming back is "opening the compass": if I am tracing someone, look again
    /// (the server re-checks every safety rule on every look). Leaving shares my own position one last time.
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active {
            start()
            if case .active = state { Task { await locate(manual: false) } }
        } else {
            // Someone may trace me: keep syncing in the background (the app stays alive on background location while a grant
            // is live, as the consent says), so a look is answered with a fresh position within seconds.
            if !isBusy && watchers.isEmpty { stop() }
            if !watchers.isEmpty { Task { await shareMyPosition(force: true) } }
        }
    }

    private var interval: TimeInterval {
        if isBusy || !incoming.isEmpty { return busyInterval }
        if !watchers.isEmpty { return watchingInterval }
        return idleInterval
    }

    // MARK: Following

    /// Point (or guide) the compass at the friend's last known position. Pointing and guiding are the paid part.
    func follow(guide: Bool) {
        guard isEntitled() else { needsUpgrade = true; return }
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

    /// Called when the purchase state changes, so the arrow appears (or goes) straight away.
    func entitlementChanged() { recomputeReading() }

    // MARK: Actions as the tracer

    /// Ask a friend for permission to trace them. Nothing is shared unless they say yes.
    func request(_ friend: Friend, hours: Double) async {
        guard isEntitled() else { needsUpgrade = true; return }
        epoch += 1
        requestError = nil
        await leaveTarget()
        state = .waiting(friend)
        do {
            try await api.requestTrace(friendId: friend.id, hours: TraceWindow.clamp(hours))
            start()
        } catch {
            state = nil
            switch (error as? FriendsError)?.httpStatus {
            case 402: needsUpgrade = true
            default: requestError = error.localizedDescription
            }
        }
    }

    /// A hint to show before the tracer looks at, or asks, someone else: leaving the current friend ends a permission that was
    /// only allowed once (or withdraws a request still waiting). nil when nothing would be lost.
    func switchWarning(to friend: Friend) -> String? {
        guard let current = targetFriend, current.id != friend.id else { return nil }
        switch state {
        case .waiting: return "Your request to \(current.username) will be withdrawn."
        case .active where heldKinds[current.id] == .oneoff:
            return "\(current.username) only allowed tracing once. If you switch, you’ll need to ask them again."
        default: return nil
        }
    }

    /// Look at a friend whose permission is already live (switching from whoever I was looking at).
    func trace(_ friend: Friend) async {
        guard isEntitled() else { needsUpgrade = true; return }
        if case .active(let current) = state, current.id == friend.id { return }
        guard heldTraces.contains(friend.id) else { return }
        epoch += 1
        await leaveTarget()
        state = .active(friend)
        locateReadyAt = nil
        await locate(manual: false)
    }

    /// "Request new location": at most once every 2 minutes (the server enforces it too).
    func locate(manual: Bool) async {
        guard case .active(let friend) = state else { return }
        guard isEntitled() else { needsUpgrade = true; return }
        if locateCountdown() > 0 { return }
        let distance: Double? = {
            guard let me = myPosition(), let peer = peerPosition else { return nil }
            return CompassManager.distance(from: me, to: peer.coordinate)
        }()
        do {
            let result = try await api.locate(traceeId: friend.id, distanceMeters: distance)
            guard case .active(let current) = state, current.id == friend.id else { return }     // moved on while waiting
            locateReadyAt = now().addingTimeInterval(result.retryAfter ?? TraceWindow.locateInterval)
            if let position = result.position {
                peerPosition = position; peerPositionAt = now(); noLocationYet = false
                if following == friend.id { onFriendPosition?(friend, position.coordinate) }
            } else if peerPosition == nil {
                noLocationYet = true
            }
            justAccepted = false
            recomputeReading()
            updateRanging()
            if (result.position?.ageSeconds ?? .infinity) > 20 { collectFreshFix(for: friend) }
        } catch {
            guard case .active(let current) = state, current.id == friend.id else { return }
            switch (error as? FriendsError)?.httpStatus {
            case 429:
                if case .status(_, _, let retry)? = error as? FriendsError { locateReadyAt = now().addingTimeInterval(retry ?? TraceWindow.locateInterval) }
            case 402:
                planOver()
            case 403:
                cannotBeTraced()
            default:
                break                                // offline or a hiccup: keep what is on screen and try again later
            }
        }
    }

    /// The other phone answers a request within seconds (it syncs every 10 s and uploads the moment it sees the look). Re-read a few
    /// times for up to about 25 s to collect that fresh fix: these re-reads are not new requests.
    private func collectFreshFix(for friend: Friend) {
        followUpTask?.cancel()
        let before = locationAge ?? .infinity
        fetchingFresh = true
        followUpTask = Task { [weak self] in
            defer { Task { @MainActor in self?.fetchingFresh = false } }
            for _ in 0..<6 {
                guard let self else { return }
                await self.sleep(4)
                guard !Task.isCancelled, case .active(let current) = self.state, current.id == friend.id else { return }
                guard let result = try? await self.api.locateFollowUp(traceeId: friend.id), let position = result.position else { continue }
                if position.ageSeconds < before {
                    self.peerPosition = position; self.peerPositionAt = self.now(); self.noLocationYet = false
                    if self.following == friend.id { self.onFriendPosition?(friend, position.coordinate) }
                    self.recomputeReading(); self.updateRanging()
                    if position.ageSeconds <= 15 { return }
                }
            }
        }
    }

    /// Stop looking at this friend (or withdraw the request). A one-off ends; a "keep tracing" permission stays until its
    /// time is up, and the friend stays in the row to pick up again.
    func end() async {
        let friend = targetFriend
        epoch += 1
        clearTarget()
        if let friend { await api.releaseTrace(traceeId: friend.id) }
    }

    // MARK: Up close

    var cameraDirectionAvailable: Bool { ranging.cameraAssistanceAvailable }
    var directionWithoutCamera: Bool { ranging.directionWithoutCamera }
    var cameraOn: Bool { ranging.cameraAssistance }
    var coaching: String? { ranging.coaching }
    /// UWB is measuring right now (a reading under 3 s old) for the friend I am looking at.
    var uwbLive: Bool {
        guard case .active(let friend) = state, uwbFriendId == friend.id, let latest = ranging.latestReading else { return false }
        return now().timeIntervalSince(latest.at) <= TraceFusion.uwbFreshSeconds
    }

    /// "Show direction": on iPhone 14 and later the arrow needs the camera's help (it tracks how the phone moves).
    func showDirection() {
        guard uwbFriendId != nil, ranging.cameraAssistanceAvailable else { return }
        ranging.setCameraAssistance(true)
        objectWillChange.send()
    }

    func hideDirectionCamera() { ranging.setCameraAssistance(false); objectWillChange.send() }

    /// What every input looks like right now, for the debug readout (no coordinates).
    func diagnostics(myAccuracy: Double?) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Mode", reading.map { $0.source == .uwb ? "UWB" : ($0.hasUsefulDirection ? "GPS arrow" : "GPS nearby (no arrow)") } ?? "none"))
        if let r = reading {
            rows.append(("Distance", r.distanceText))
            if let u = r.uncertaintyDegrees { rows.append(("GPS direction ±", "\(Int(u))°")) }
            if let b = r.relativeBearing { rows.append(("UWB angle", "\(Int(b))°")) }
        }
        rows.append(("Their fix age", locationAge.map { "\(Int($0)) s" } ?? "none"))
        rows.append(("Their accuracy", peerPosition?.accuracy.map { "±\(Int($0)) m" } ?? "unknown"))
        rows.append(("My accuracy", myAccuracy.map { "±\(Int($0)) m" } ?? "unknown"))
        rows.append(("UWB hardware", ranging.capability.canRange ? (ranging.directionWithoutCamera ? "distance + direction" : (ranging.cameraAssistanceAvailable ? "distance; direction with camera" : "distance only")) : "none"))
        rows.append(("UWB", uwbFriendId == nil ? "off" : (uwbLive ? "ranging" : "waiting for their phone")))
        rows.append(("Camera assist", ranging.cameraAssistance ? (ranging.coaching ?? "settled") : "off"))
        rows.append(("Fresh fix", fetchingFresh ? "waiting" : "-"))
        return rows
    }

    /// Start Ultra Wideband now rather than waiting to be within about 40 m of the last location.
    func findPrecisely() {
        guard case .active(let friend) = state, ranging.capability.canRange else { return }
        wantsPrecise = true
        startRanging(friend)
    }

    // MARK: Actions as the traced person

    /// Allow a tracer. Needs the phone's owner to confirm first (Face ID, the phone passcode, or the app passcode).
    func grant(_ request: IncomingTrace, hours: Double, kind: GrantKind) async -> GrantOutcome {
        errorMessage = nil
        switch await owner.authenticate(reason: "Allow \(request.friend.username) to see where you are") {
        case .success: break
        case .cancelled: return .cancelled
        case .failed, .lockedOut:
            errorMessage = "We couldn't confirm it's you, so nothing was allowed."
            return .notVerified
        }
        let length = min(TraceWindow.clamp(hours), request.requestedHours)
        do {
            try await api.answerTrace(tracerId: request.friend.id, grant: true, hours: length, kind: kind, consentVersion: ConsentCopy.version)
            epoch += 1
            await poll()
            return .granted
        } catch {
            errorMessage = error.localizedDescription
            await poll()                                  // the request may have expired: the next sync says so
            return .failed(error.localizedDescription)
        }
    }

    /// Say no. (Needs no confirmation: refusing is always the safe direction.)
    func decline(_ request: IncomingTrace) async {
        errorMessage = nil
        incoming.removeAll { $0.id == request.id }
        epoch += 1
        do { try await api.answerTrace(tracerId: request.friend.id, grant: false, hours: nil, kind: nil, consentVersion: nil) }
        catch { errorMessage = error.localizedDescription }
        clearNotificationIfNoRequests()
    }

    /// Stop someone from tracing me, now. Never needs a check, never throttled. If the server cannot be reached the person
    /// is told plainly that it is not stopped yet.
    @discardableResult
    func revoke(_ watcher: Watcher) async -> Bool {
        let before = watchers
        watchers.removeAll { $0.id == watcher.id }
        if stillTracing?.id == watcher.id { stillTracing = nil }
        epoch += 1
        do {
            try await api.revokeTrace(tracerId: watcher.friend.id)
            stopRangingIfFor(watcher.friend.id)
            return true
        } catch {
            watchers = before
            errorMessage = "We couldn't stop \(watcher.friend.username) just now. Check your connection and try again: it is still on."
            return false
        }
    }

    func revokeAll() async {
        for watcher in watchers { await revoke(watcher) }
    }

    func dismissStillTracing() { stillTracing = nil }

    func clearError() { errorMessage = nil }

    // MARK: Polling

    /// One sync: fetch both roles in a single request, reconcile, and (when someone may see me) share my position and manage
    /// the radio. The background loop calls this; tests call it directly.
    func poll() async {
        if case .notice = state, now() >= noticeUntil { state = nil; reading = nil }
        if justAccepted, now() >= acceptedUntil { justAccepted = false }

        let startedAt = epoch
        let snapshot: GrantsSnapshot
        do {
            snapshot = try await api.grantsSnapshot()
        } catch {
            return                         // a dropped connection must not end a trace: keep what we have
        }
        guard startedAt == epoch else { return }      // something local happened while this was in flight
        await reconcileTraced(snapshot.asTraced)
        await reconcileTracer(snapshot)
        await shareMyPosition(force: false)
        updateRanging()
        recomputeReading()
    }

    // The traced side: requests and permissions.
    private func reconcileTraced(_ entries: [TracedEntry]) async {
        let known = friends()
        var unknownTracer = false
        var requests: [IncomingTrace] = []
        var active: [Watcher] = []
        for entry in entries {
            guard let friend = known.first(where: { $0.id == entry.tracerId }) else { unknownTracer = true; continue }
            if entry.isRequest {
                requests.append(IncomingTrace(friend: friend, requestedHours: entry.requestedHours ?? 1,
                                              requestedAt: entry.requestedAt,
                                              expiresAt: entry.requestExpiresAt.map { Date(timeIntervalSince1970: $0) }))
            } else if entry.isActive, let until = entry.until {
                active.append(Watcher(friend: friend, kind: entry.kind, until: Date(timeIntervalSince1970: until),
                                      lastLookedAt: entry.lastLookedAt.map { Date(timeIntervalSince1970: $0) }, band: entry.band))
                if let looked = entry.lastLookedAt {
                    if let before = lastLooked[friend.id], looked > before { lookedSinceUpload = true }     // they looked: share a fresh position now
                    lastLooked[friend.id] = looked
                }
                if entry.stillTracing == true { raiseStillTracing(friend) }
            }
        }
        if unknownTracer, now().timeIntervalSince(lastFriendsRefresh) > 60 { lastFriendsRefresh = now(); await refreshFriends() }

        for request in requests {
            let key = "\(request.friend.id)#\(request.requestedAt ?? 0)"
            if announced.insert(key).inserted, !sceneActive {
                notifier.incomingRequest(from: request.friend.username); notificationShown = true
            }
        }
        if requests.isEmpty { clearNotification() }
        incoming = requests
        watchers = active
        if let current = stillTracing, !active.contains(where: { $0.id == current.id }) { stillTracing = nil }
        lastLooked = lastLooked.filter { key, _ in active.contains { $0.id == key } }
    }

    private func raiseStillTracing(_ friend: Friend) {
        if !sceneActive { notifier.stillTracing(name: friend.username) }
        if stillTracing == nil { stillTracing = friend }
    }

    // The tracer side: what became of my request, and the plan.
    private func reconcileTracer(_ snapshot: GrantsSnapshot) async {
        heldTraces = Set(snapshot.asTracer.filter(\.isActive).map(\.traceeId))
        heldKinds = Dictionary(uniqueKeysWithValues: snapshot.asTracer.filter(\.isActive).map { ($0.traceeId, $0.kind) })
        if let plan = snapshot.plan {
            planEnds = plan.until.map { Date(timeIntervalSince1970: $0) }
            if !plan.active, isBusy { planOver(); return }
        }
        guard let friend = targetFriend else { return }
        let entry = snapshot.asTracer.first { $0.traceeId == friend.id }
        switch state {
        case .waiting:
            guard let entry else { cannotBeTraced(); return }       // declined, expired, unfriended or blocked: all look alike
            if entry.isActive { await becomeActive(friend) }
        case .active:
            if entry?.isActive != true { cannotBeTraced() }
        default:
            break
        }
    }

    private func becomeActive(_ friend: Friend) async {
        state = .active(friend)
        justAccepted = true
        acceptedUntil = now().addingTimeInterval(8)
        peerPosition = nil; noLocationYet = false; locateReadyAt = nil; fusion.reset()
        await locate(manual: false)
    }

    /// The one answer a tracer ever gets when tracing is not possible, whatever the reason.
    private func cannotBeTraced() {
        clearTarget()
        showNotice(TraceCopy.cannotTrace)
    }

    private func planOver() {
        clearTarget()
        showNotice(TraceCopy.planEnded)
        needsUpgrade = true
    }

    private func leaveTarget() async {
        let friend = targetFriend
        clearTarget()
        if let friend { await api.releaseTrace(traceeId: friend.id) }
    }

    private func clearTarget() {
        followUpTask?.cancel(); followUpTask = nil; fetchingFresh = false
        uwbHistory.removeAll(); closing = nil
        stopRanging(); wantsPrecise = false
        state = nil; reading = nil; peerPosition = nil; fusion.reset()
        justAccepted = false; noLocationYet = false; locateReadyAt = nil
        stopFollowing()
    }

    private func showNotice(_ text: String) {
        state = .notice(text)
        noticeUntil = now().addingTimeInterval(noticeLife)
        reading = nil
    }

    private func clearNotification() {
        guard notificationShown else { return }
        notificationShown = false
        notifier.clearIncoming()
    }

    private func clearNotificationIfNoRequests() { if incoming.isEmpty { clearNotification() } }

    // MARK: Sharing my own position (only while someone may see it)

    private func shareMyPosition(force: Bool) async {
        guard !watchers.isEmpty, let me = myPosition() else { return }
        let due: Bool
        if let last = lastUpload {
            let elapsed = now().timeIntervalSince(last.at)
            let moved = CompassManager.distance(from: last.coordinate, to: me)
            due = force || lookedSinceUpload || elapsed >= uploadAtLeastEvery || (elapsed >= uploadMovedAfter && moved >= uploadMoveMetres)
        } else {
            due = true
        }
        guard due else { return }
        do {
            try await api.uploadPosition(me, accuracy: myAccuracy())
            lastUpload = (now(), me)
            lookedSinceUpload = false
        } catch {
            /* the next sync tries again; a failed upload must never end anything */
        }
    }

    // MARK: Ultra Wideband

    private static func isClose(_ band: String?) -> Bool { band == "under 50 m" || band == "under 200 m" }

    private func updateRanging() {
        guard ranging.capability.canRange else { return }
        // As the tracer: GPS gets me within about 40 m of where they were last seen, then the radio takes over.
        if case .active(let friend) = state {
            let gps: Double? = {
                guard let me = myPosition(), let peer = peerPosition else { return nil }
                return CompassManager.distance(from: me, to: peer.coordinate)
            }()
            if wantsPrecise || TraceFusion.wantsUWB(gpsMeters: gps, running: uwbFriendId == friend.id) { startRanging(friend) }
            else if uwbFriendId == friend.id { stopRanging() }
            return
        }
        // As the traced person: someone who looked from close by a moment ago is probably walking up to me. The radio is
        // only ever a measurement between our two phones; nothing about it is shown to me.
        let nearby = watchers.first { Self.isClose($0.band) && ($0.lastLookedAt.map { now().timeIntervalSince($0) < 600 } ?? false) }
        if let nearby { startRanging(nearby.friend) } else if uwbFriendId != nil { stopRanging() }
    }

    private func startRanging(_ friend: Friend) {
        guard uwbFriendId != friend.id else { return }
        ranging.start(with: friend)
        uwbFriendId = friend.id
    }

    private func stopRanging() {
        guard uwbFriendId != nil else { return }
        ranging.stop(); uwbFriendId = nil
        uwbHistory.removeAll(); closing = nil
    }

    private func stopRangingIfFor(_ id: String) { if uwbFriendId == id { stopRanging() } }

    /// Called every sync and on every Ultra Wideband reading.
    private func recomputeReading() {
        guard case .active(let friend) = state else { return }
        guard isEntitled() else { reading = nil; return }
        let uwb: (reading: ProximityReading, ageSeconds: Double)? = uwbFriendId == friend.id
            ? ranging.latestReading.map { (reading: $0.reading, ageSeconds: now().timeIntervalSince($0.at)) } : nil
        // The age shown is how old their location is *now*, not when it was fetched.
        let aged = peerPosition.map {
            TracePeerPosition(latitude: $0.latitude, longitude: $0.longitude, accuracy: $0.accuracy,
                              ageSeconds: $0.ageSeconds + now().timeIntervalSince(peerPositionAt))
        }
        reading = fusion.reading(me: myPosition(), peer: aged, uwb: uwb, myAccuracy: myAccuracy())
        // Warmer / colder from the last couple of seconds of radio distance.
        if let uwb, uwb.ageSeconds <= TraceFusion.uwbFreshSeconds {
            uwbHistory.append((uwb.reading.meters, now()))
            uwbHistory.removeAll { now().timeIntervalSince($0.at) > 4 }
            if let oldest = uwbHistory.first, now().timeIntervalSince(oldest.at) >= 1.5 {
                let change = uwb.reading.meters - oldest.meters
                closing = change < -0.3 ? true : (change > 0.3 ? false : nil)
            }
        } else if !uwbHistory.isEmpty {
            uwbHistory.removeAll(); closing = nil
        }
    }
}

// MARK: - Network (the same authenticated client as friends)

extension FriendsManager: TraceAPI {
    func grantsSnapshot() async throws -> GrantsSnapshot {
        try await request(method: "GET", path: "/grants")
    }

    func requestTrace(friendId: String, hours: Double) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/grants/request",
                                                 body: ["friendId": friendId, "hours": hours])
    }

    func answerTrace(tracerId: String, grant: Bool, hours: Double?, kind: GrantKind?, consentVersion: String?) async throws {
        var body: [String: Any] = ["tracerId": tracerId, "action": grant ? "grant" : "decline"]
        if grant {
            body["confirmed"] = true                      // the app has shown the second confirmation and checked the owner
            if let hours { body["hours"] = hours }
            if let kind { body["kind"] = kind.rawValue }
            if let consentVersion { body["consentVersion"] = consentVersion }
        }
        let _: EmptyResponse = try await request(method: "POST", path: "/grants/respond", body: body)
    }

    func revokeTrace(tracerId: String) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/grants/revoke", body: ["tracerId": tracerId])
    }

    func releaseTrace(traceeId: String) async {
        let _: EmptyResponse? = try? await request(method: "POST", path: "/grants/release", body: ["traceeId": traceeId])
    }

    func uploadPosition(_ coordinate: CLLocationCoordinate2D, accuracy: Double) async throws {
        let _: EmptyResponse = try await request(method: "PUT", path: "/grants/position", body: [
            "lat": coordinate.latitude, "lon": coordinate.longitude, "acc": max(0, accuracy),
        ])
    }

    func locateFollowUp(traceeId: String) async throws -> LocateResult {
        try await request(method: "POST", path: "/grants/locate", body: ["traceeId": traceeId, "followUp": true])
    }

    func locate(traceeId: String, distanceMeters: Double?) async throws -> LocateResult {
        var body: [String: Any] = ["traceeId": traceeId]
        if let distanceMeters { body["distanceM"] = distanceMeters }     // the server keeps only a band
        return try await request(method: "POST", path: "/grants/locate", body: body)
    }
}
