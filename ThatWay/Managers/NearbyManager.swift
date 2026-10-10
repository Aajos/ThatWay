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
    /// This phone's archived discovery token, base64.
    func localToken() -> String?
    @discardableResult func run(peerToken: String) -> Bool
    func stop()
}

@MainActor
final class NearbyManager: ObservableObject {
    @Published private(set) var state: NearbyState = .idle
    @Published private(set) var friend: Friend?
    /// The phone tells the watch how close the friend is (nil when the session ends).
    var onWatchState: ((ProximityWatchState?) -> Void)?

    private let api: NearbyOfferAPI
    private let capability: () -> NearbyCapability
    private let isConfigured: () -> Bool
    private let makeSession: () -> ProximitySession
    private let pollInterval: Duration
    private let republishEvery: Int

    private var session: ProximitySession?
    private var loop: Task<Void, Never>?
    private var smoother = ProximitySmoother()
    private var lastSentToWatch: (meters: Int?, band: ProximityBand, at: Date)?
    private var ranging = false

    init(api: NearbyOfferAPI,
         capability: @escaping () -> NearbyCapability,
         isConfigured: @escaping () -> Bool = { Config.apiConfigured },
         makeSession: @escaping () -> ProximitySession,
         pollInterval: Duration = .seconds(2),
         republishEvery: Int = 15) {
        self.api = api; self.capability = capability; self.isConfigured = isConfigured; self.makeSession = makeSession
        self.pollInterval = pollInterval; self.republishEvery = republishEvery
    }

    var isActive: Bool { loop != nil }

    func start(with friend: Friend) {
        stop()
        self.friend = friend
        guard capability().canRange else { state = .unsupported; return }
        guard isConfigured() else {
            state = .failed("Friends aren't switched on yet, so finding a friend isn't available.")
            return
        }
        let session = makeSession()
        guard let token = session.localToken() else { state = .unsupported; return }
        self.session = session
        smoother.reset(); ranging = false; lastSentToWatch = nil
        state = .connecting

        session.onUpdate = { [weak self] meters, bearing in self?.handleReading(meters: meters, bearing: bearing) }
        session.onEnded = { [weak self] in self?.handleEnded() }

        loop = Task { [weak self] in
            var tick = 0
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    if tick % self.republishEvery == 0 {            // keeps our offer inside its 2-minute life
                        try await self.api.putOffer(friendId: friend.id, token: token, kind: .uwb)
                    }
                    if !self.ranging {
                        let offers = try await self.api.offers()
                        if let theirs = offers.first(where: { $0.friendId == friend.id && $0.kind == .uwb }),
                           self.session?.run(peerToken: theirs.token) == true {
                            self.ranging = true
                        } else if case .connecting = self.state {
                            self.state = .waiting
                        }
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

    func stop() {
        loop?.cancel(); loop = nil
        session?.onUpdate = nil; session?.onEnded = nil
        session?.stop(); session = nil
        ranging = false
        if let id = friend?.id { Task { await api.endOffers(friendId: id) } }
        if state != .idle { onWatchState?(nil) }
        friend = nil
        state = .idle
    }

    private func handleReading(meters: Double, bearing: Double?) {
        guard let friend else { return }
        let band = smoother.add(meters: meters)
        let smoothed = smoother.meters ?? meters
        let reading = ProximityReading(meters: smoothed, band: band, relativeBearing: bearing)
        state = .ranging(reading)

        // The watch needs the news, not every sample: when the band or whole metres change, at most once a second.
        let whole = Int(smoothed.rounded())
        let now = Date()
        if let last = lastSentToWatch, last.band == band, last.meters == whole || now.timeIntervalSince(last.at) < 1 { return }
        lastSentToWatch = (whole, band, now)
        onWatchState?(ProximityWatchState(friendName: friend.username, band: band, meters: whole))
    }

    private func handleEnded() {
        loop?.cancel(); loop = nil
        session?.stop(); session = nil
        ranging = false
        if let id = friend?.id { Task { await api.endOffers(friendId: id) } }
        onWatchState?(nil)
        state = .lost
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
