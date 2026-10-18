//
//  NearbyManager.swift
//  ThatWay
//
//  "Find a friend nearby": two phones range each other over Ultra Wideband with Apple's Nearby Interaction. Each phone
//  makes a session, publishes its discovery token to the backend for that one friend (`PUT /nearby/offers`), polls for
//  the friend's token (`GET /nearby/offers`) and starts ranging the moment it appears. The backend only relays tokens
//  between accepted friends and forgets them after two minutes. No location is sent anywhere: the phones measure the
//  distance between themselves.
//
//  The hardware lives behind `ProximitySession` and the backend behind `NearbyOfferAPI`, so the exchange logic is
//  unit-tested without a UWB phone. (The simulator and iPhone SE have no UWB: they report `.unsupported`.)
//

import Foundation
import Combine
import ThatWayCore

enum NearbyState: Equatable {
    case idle
    /// This phone cannot range (no Ultra Wideband).
    case unsupported
    case connecting
    /// Our token is published; waiting for the friend to open Find on their phone.
    case waiting
    case ranging(ProximityReading)
    /// The session ended (the friend left, or the connection timed out).
    case lost
    case failed(String)
}

@MainActor
protocol NearbyOfferAPI: AnyObject {
    func putOffer(friendId: String, token: String, kind: NearbyKind) async throws
    func offers() async throws -> [NearbyOffer]
    func endOffers(friendId: String) async
}

/// One Nearby Interaction session. `onUpdate` reports metres and, if the hardware knows it, the friend's bearing
/// relative to the top of the phone in degrees (−180…180, right is positive).
@MainActor
protocol ProximitySession: AnyObject {
    var onUpdate: ((_ meters: Double, _ bearing: Double?) -> Void)? { get set }
    /// The peer left, timed out, or the session was invalidated.
    var onEnded: (() -> Void)? { get set }
    /// What the person should do for camera-assisted direction to settle ("move your phone slowly"), nil once it has.
    var onCoaching: ((String?) -> Void)? { get set }
    func setCameraAssistance(_ on: Bool)
    /// This phone's archived discovery token, base64.
    func localToken() -> String?
    @discardableResult func run(peerToken: String) -> Bool
    func stop()
}

/// What the trace manager needs from the UWB layer (so it can be tested without hardware).
@MainActor
protocol ProximityRanging: AnyObject {
    var capability: NearbyCapability { get }
    /// The newest Ultra Wideband reading and when it arrived; nil until the first one of this session.
    var latestReading: (reading: ProximityReading, at: Date)? { get }
    /// Called on every new reading, so the pill can follow UWB at its own rate instead of the polling rate.
    var onReading: (() -> Void)? { get set }
    /// Whether this phone can give a direction once the camera is on (iPhone 14 and later).
    var cameraAssistanceAvailable: Bool { get }
    /// Whether this phone gives a direction from the radio alone (iPhone 11 to 13).
    var directionWithoutCamera: Bool { get }
    var cameraAssistance: Bool { get }
    /// Instructions while camera-assisted direction settles; nil when it has (or the camera is off).
    var coaching: String? { get }
    func setCameraAssistance(_ on: Bool)
    func start(with friend: Friend)
    func stop()
}

@MainActor
final class NearbyManager: ObservableObject, ProximityRanging {
    @Published private(set) var state: NearbyState = .idle
    @Published private(set) var friend: Friend?
    @Published private(set) var cameraAssistance = false
    @Published private(set) var coaching: String?
    private(set) var latestReading: (reading: ProximityReading, at: Date)?
    var onReading: (() -> Void)?
    var cameraAssistanceAvailable: Bool { NearbySession.supportsCameraAssistance }
    var directionWithoutCamera: Bool { NearbySession.directionWithoutCamera }

    func setCameraAssistance(_ on: Bool) {
        cameraAssistance = on && cameraAssistanceAvailable
        session?.setCameraAssistance(cameraAssistance)
        if !cameraAssistance { coaching = nil }
        onReading?()
    }

    private let api: NearbyOfferAPI
    private let capabilityProvider: () -> NearbyCapability
    private let isConfigured: () -> Bool
    private let makeSession: () -> ProximitySession
    private let pollInterval: Duration
    private let republishEvery: Int
    private let staleAfter: TimeInterval
    private let now: () -> Date

    private var session: ProximitySession?
    private var loop: Task<Void, Never>?
    private var smoother = ProximitySmoother()
    private var ranging = false
    /// The friend's token we last handed to the session, and when: if readings stop, their token may have changed
    /// (they closed and reopened Find, or the app was killed and an old offer lingered).
    private var usedPeerToken: String?
    private var ranAt = Date.distantPast

    init(api: NearbyOfferAPI,
         capability: @escaping () -> NearbyCapability,
         isConfigured: @escaping () -> Bool = { Config.apiConfigured },
         makeSession: @escaping () -> ProximitySession,
         pollInterval: Duration = .seconds(2),
         republishEvery: Int = 15,
         staleAfter: TimeInterval = 6,
         now: @escaping () -> Date = Date.init) {
        self.api = api; self.capabilityProvider = capability; self.isConfigured = isConfigured; self.makeSession = makeSession
        self.pollInterval = pollInterval; self.republishEvery = republishEvery
        self.staleAfter = staleAfter; self.now = now
    }

    var capability: NearbyCapability { capabilityProvider() }
    var isActive: Bool { loop != nil }

    func start(with friend: Friend) {
        stop()
        self.friend = friend
        guard capability.canRange else { state = .unsupported; return }
        guard isConfigured() else {
            state = .failed("Friends aren't switched on yet, so finding a friend isn't available.")
            return
        }
        let session = makeSession()
        guard let token = session.localToken() else { state = .unsupported; return }
        self.session = session
        smoother.reset(); ranging = false; latestReading = nil; usedPeerToken = nil; ranAt = .distantPast
        state = .connecting

        session.onUpdate = { [weak self] meters, bearing in self?.handleReading(meters: meters, bearing: bearing) }
        session.onEnded = { [weak self] in self?.handleEnded() }
        session.onCoaching = { [weak self] text in self?.coaching = text; self?.onReading?() }
        if cameraAssistance { session.setCameraAssistance(true) }

        loop = Task { [weak self] in
            var tick = 0
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    if tick % self.republishEvery == 0 {            // keeps our offer inside its 2-minute life
                        try await self.api.putOffer(friendId: friend.id, token: token, kind: .uwb)
                    }
                    if self.needsOffers {
                        let offers = try await self.api.offers()
                        self.adopt(offers.first(where: { $0.friendId == friend.id && $0.kind == .uwb }))
                    }
                    failures = 0
                } catch {
                    failures += 1
                    if failures >= 3 { self.state = .failed(error.localizedDescription) }
                }
                tick += 1
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    /// Poll for the friend's token until ranging has started, and again whenever readings have gone quiet for
    /// `staleAfter` seconds: that is the signature of a dead token (their old offer) or a friend who restarted.
    private var needsOffers: Bool {
        guard ranging else { return true }
        let lastSign = max(latestReading?.at ?? .distantPast, ranAt)
        return now().timeIntervalSince(lastSign) > staleAfter
    }

    private func adopt(_ offer: NearbyOffer?) {
        guard let offer else {
            if !ranging, case .connecting = state { state = .waiting }
            return
        }
        guard offer.token != usedPeerToken else { return }          // same token: nothing new to learn
        if session?.run(peerToken: offer.token) == true {
            usedPeerToken = offer.token
            ranging = true
            ranAt = now()
            latestReading = nil
            smoother.reset()
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        session?.onUpdate = nil; session?.onEnded = nil; session?.onCoaching = nil
        session?.stop(); session = nil
        cameraAssistance = false; coaching = nil
        ranging = false; latestReading = nil; usedPeerToken = nil
        if let id = friend?.id { Task { await api.endOffers(friendId: id) } }
        friend = nil
        state = .idle
    }

    private func handleReading(meters: Double, bearing: Double?) {
        guard friend != nil else { return }
        let band = smoother.add(meters: meters)
        let reading = ProximityReading(meters: smoother.meters ?? meters, band: band, relativeBearing: bearing)
        latestReading = (reading, now())
        state = .ranging(reading)
        onReading?()
    }

    private func handleEnded() {
        loop?.cancel(); loop = nil
        session?.stop(); session = nil
        ranging = false; latestReading = nil; usedPeerToken = nil
        if let id = friend?.id { Task { await api.endOffers(friendId: id) } }
        state = .lost
        onReading?()
    }
}

extension FriendsManager: NearbyOfferAPI {
    func putOffer(friendId: String, token: String, kind: NearbyKind) async throws {
        let _: EmptyResponse = try await request(method: "PUT", path: "/nearby/offers",
                                                 body: ["friendId": friendId, "token": token, "kind": kind.rawValue])
    }

    func offers() async throws -> [NearbyOffer] {
        try await request(method: "GET", path: "/nearby/offers")
    }

    func endOffers(friendId: String) async {
        let _: EmptyResponse? = try? await request(method: "DELETE", path: "/nearby/offers/\(friendId)")
    }
}
